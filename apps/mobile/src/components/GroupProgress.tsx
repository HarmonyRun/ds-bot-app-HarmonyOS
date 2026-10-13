import React, { useEffect, useState } from "react";
import { AppState, ScrollView, Text, View } from "react-native";
import { MobileClient } from "@ds-bot/mobile-sdk";
import { Room, TeamState } from "../types";
import { useTheme } from "../theme";
import { useI18n } from "../i18n";
import { BotAvatar } from "./BotAvatar";

interface Round {
  callId: string;
  speaking: string | null;
  replies: { botId: string; kind?: string }[];
}

/** Round progress and the host's current work/approval evidence for these members. */
export function GroupProgress({
  client,
  room,
  team,
  running,
  online,
}: {
  client: MobileClient;
  room: Room;
  team: TeamState;
  running: boolean;
  online: boolean;
}) {
  const t = useTheme();
  const { tr } = useI18n();
  const [rounds, setRounds] = useState<Round[]>([]);
  const [unavailable, setUnavailable] = useState(false);
  const busyMembers = room.members.filter(id => team.work?.bots[id] || team.work?.approvals.some(approval => approval.botId === id));
  useEffect(() => {
    let alive = true;
    let generation = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let foreground = AppState.currentState === "active";
    setRounds([]);
    setUnavailable(false);
    if (!running || !online) return;
    const poll = async (run: number) => {
      if (!alive || !foreground || run !== generation) return;
      try {
        const result = await client.action<Round[]>("room-progress", {
          roomId: room.id,
        });
        if (!alive || !foreground || run !== generation) return;
        setRounds(
          Array.isArray(result)
            ? result.filter((round) => round && Array.isArray(round.replies))
            : [],
        );
        setUnavailable(false);
      } catch {
        if (!alive || !foreground || run !== generation) return;
        setRounds([]);
        setUnavailable(true);
      }
      if (alive && foreground && run === generation)
        timer = setTimeout(() => void poll(run), 1000);
    };
    const start = () => {
      generation++;
      clearTimeout(timer);
      if (foreground) void poll(generation);
    };
    start();
    const subscription = AppState.addEventListener("change", (state) => {
      foreground = state === "active";
      setRounds([]);
      setUnavailable(false);
      start();
    });
    return () => {
      alive = false;
      generation++;
      clearTimeout(timer);
      subscription.remove();
    };
  }, [client, room.id, running, online]);
  if (!online || (!running && !busyMembers.length) || (!rounds.length && !unavailable && !busyMembers.length)) return null;
  if (unavailable && !busyMembers.length)
    return (
      <Text
        style={{
          fontSize: 11,
          color: t.muted,
          paddingHorizontal: 12,
          paddingBottom: 6,
        }}
      >
        {tr("Group activity is temporarily unavailable.")}
      </Text>
    );
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{
        gap: 8,
        paddingHorizontal: 12,
        paddingBottom: 8,
      }}
      style={{ flexGrow: 0 }}
    >
      {(running && rounds.length ? room.members : busyMembers).map((id) => {
        const bot = team.bots.find((item) => item.id === id);
        if (!bot) return null;
        const speaking = rounds.some((round) => round.speaking === id);
        const replies = rounds
          .flatMap((round) => round.replies)
          .filter((reply) => reply.botId === id);
        const reply = replies[replies.length - 1];
        const waiting = team.work?.approvals.some(approval => approval.botId === id);
        const doing = team.work?.bots[id];
        const status = waiting ? tr("Waiting for approval") : speaking
          ? tr("Typing…")
          : reply?.kind === "failed"
            ? tr("Could not answer")
            : reply?.kind === "lookup"
              ? tr("Looking back through the chat")
              : reply
                ? tr("Replied")
                : doing ? tr("Working") : "";
        return (
          <View
            key={id}
            accessibilityLabel={`${bot.name}${status ? ` · ${status}` : ""}`}
            style={{
              flexDirection: "row",
              alignItems: "center",
              gap: 6,
              borderRadius: 999,
              minHeight: 44,
              paddingVertical: 7,
              paddingHorizontal: 12,
              borderWidth: 1,
              borderColor: speaking ? t.accent : t.line,
              backgroundColor: speaking ? t.soft : t.surface,
            }}
          >
            <BotAvatar bot={bot} size={22} live={speaking} />
            <View>
              <Text style={{ fontSize: 11, color: t.ink }}>{bot.name}</Text>
              {!!status && (
                <Text
                  style={{
                    fontSize: 10,
                    color:
                      reply?.kind === "failed" && !speaking ? t.error : t.muted,
                  }}
                >
                  {status}
                </Text>
              )}
            </View>
          </View>
        );
      })}
    </ScrollView>
  );
}
