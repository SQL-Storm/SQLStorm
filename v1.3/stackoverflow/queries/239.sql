-- {"query": "239.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5248} 
WITH
tag_posts AS (
  SELECT p.Id AS PostId, p.OwnerUserId, unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
user_tag_counts AS (
  SELECT OwnerUserId AS UserId, Tag, count(*) AS TagCount
  FROM tag_posts
  GROUP BY OwnerUserId, Tag
),
badge_summary AS (
  SELECT UserId,
    count(*) AS BadgeCount,
    count(*) FILTER (WHERE Class=1) AS GoldBadges,
    count(*) FILTER (WHERE Class=2) AS SilverBadges,
    count(*) FILTER (WHERE Class=3) AS BronzeBadges,
    count(*) FILTER (WHERE TagBased) AS TagBasedBadges
  FROM Badges
  GROUP BY UserId
),
vote_summary AS (
  SELECT p.OwnerUserId AS UserId,
    count(*) AS TotalVotes,
    sum(CASE WHEN v.VoteTypeId=2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    sum(CASE WHEN v.VoteTypeId=3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    sum(CASE WHEN v.VoteTypeId=5 THEN 1 ELSE 0 END) AS FavoritesReceived
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
post_summary AS (
  SELECT
    OwnerUserId AS UserId,
    sum(CASE WHEN PostTypeId=1 THEN 1 ELSE 0 END) AS Questions,
    sum(CASE WHEN PostTypeId=2 THEN 1 ELSE 0 END) AS Answers,
    sum(CASE WHEN PostTypeId=2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = Posts.Id) THEN 1 ELSE 0 END) AS AcceptedAnswers,
    avg(CASE WHEN Score IS NOT NULL THEN Score ELSE 0 END) AS AvgScore,
    max(Score) AS MaxScore,
    sum(COALESCE(ViewCount,0)) AS TotalViews,
    count(DISTINCT Id) AS TotalPosts
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
link_summary AS (
  SELECT p.OwnerUserId AS UserId,
    sum(CASE WHEN pl.LinkTypeId=1 THEN 1 ELSE 0 END) AS OutgoingLinks,
    sum(CASE WHEN pl.LinkTypeId=3 THEN 1 ELSE 0 END) AS MarkedDuplicates
  FROM PostLinks pl
  JOIN Posts p ON p.Id = pl.PostId
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
close_summary AS (
  SELECT ph.UserId, count(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,35)) AS CloseVotes, count(*) FILTER (WHERE ph.PostHistoryTypeId IN (11,36)) AS ReopenVotes
  FROM PostHistory ph
  WHERE ph.UserId IS NOT NULL
  GROUP BY ph.UserId
),
event_stream AS (
  SELECT OwnerUserId AS UserId, CreationDate, 'post' AS EventType, Id::text AS EventId
  FROM Posts WHERE OwnerUserId IS NOT NULL
  UNION ALL
  SELECT UserId, CreationDate, 'comment' AS EventType, Id::text FROM Comments WHERE UserId IS NOT NULL
  UNION ALL
  SELECT UserId, Date AS CreationDate, 'badge' AS EventType, Id::text FROM Badges
  UNION ALL
  SELECT UserId, CreationDate, 'vote' AS EventType, Id::text FROM Votes WHERE UserId IS NOT NULL
),
user_events AS (
  SELECT
    es.UserId,
    count(*) AS EventCount,
    max(es.CreationDate) AS LastEvent,
    min(es.CreationDate) AS FirstEvent,
    date_part('epoch', max(es.CreationDate) - min(es.CreationDate)) / nullif(count(*)-1,0) AS AvgSecondsBetweenEvents
  FROM event_stream es
  GROUP BY es.UserId
),
ranked_users AS (
  SELECT u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ps.Questions,0) AS Questions,
    COALESCE(ps.Answers,0) AS Answers,
    COALESCE(ps.AcceptedAnswers,0) AS AcceptedAnswers,
    COALESCE(ps.AvgScore,0) AS AvgScore,
    COALESCE(bs.BadgeCount,0) AS BadgeCount,
    COALESCE(vs.TotalVotes,0) AS VotesReceived,
    COALESCE(ls.OutgoingLinks,0) AS Links,
    COALESCE(cs.CloseVotes,0) AS CloseVotes,
    COALESCE(ue.EventCount,0) AS EventCount,
    ue.LastEvent,
    RANK() OVER (ORDER BY COALESCE(ps.Questions,0) DESC, COALESCE(ps.Answers,0) DESC, u.Reputation DESC) AS EngagementRank
  FROM Users u
  LEFT JOIN post_summary ps ON ps.UserId = u.Id
  LEFT JOIN badge_summary bs ON bs.UserId = u.Id
  LEFT JOIN vote_summary vs ON vs.UserId = u.Id
  LEFT JOIN link_summary ls ON ls.UserId = u.Id
  LEFT JOIN close_summary cs ON cs.UserId = u.Id
  LEFT JOIN user_events ue ON ue.UserId = u.Id
)
SELECT
  ru.UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.Questions,
  ru.Answers,
  ru.AcceptedAnswers,
  ru.AvgScore,
  ru.BadgeCount,
  ru.VotesReceived,
  ru.Links,
  ru.CloseVotes,
  ru.EventCount,
  ru.LastEvent,
  ru.EngagementRank,
  (COALESCE(ru.Answers,0) + COALESCE(ru.Questions,0)) AS TotalContributions,
  CASE WHEN COALESCE(ru.Answers,0) = 0 THEN 0 ELSE round((COALESCE(ru.AcceptedAnswers,0)::numeric / ru.Answers) * 100,2) END AS AcceptedPercent,
  CASE WHEN ru.Questions>0 THEN round((ru.VotesReceived::numeric/NULLIF(ru.Questions,0)),2) ELSE NULL END AS AvgVotesPerQuestion,
  bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
  COALESCE(vs.UpVotesReceived,0) - COALESCE(vs.DownVotesReceived,0) AS NetVoteDiff,
  COALESCE(ls.MarkedDuplicates,0) AS DuplicatesMarked,
  /* Top 3 tags (tag:count) */
  (SELECT string_agg(t.tag || ':' || t.cnt, ', ' ORDER BY t.cnt DESC)
   FROM (
     SELECT Tag, count(*) AS cnt
     FROM tag_posts tp
     WHERE tp.OwnerUserId = ru.UserId
     GROUP BY Tag
     ORDER BY cnt DESC
     LIMIT 3
   ) t(tag,cnt)
  ) AS Top3Tags,
  /* Latest comment snippet */
  (SELECT substring(c.Text from 1 for 120) || CASE WHEN length(c.Text) > 120 THEN '...' ELSE '' END
   FROM Comments c
   WHERE c.UserId = ru.UserId
   ORDER BY c.CreationDate DESC
   LIMIT 1
  ) AS LatestCommentSnippet,
  /* Active in last 30 days */
  EXISTS (
    SELECT 1 FROM event_stream es2 WHERE es2.UserId = ru.UserId AND es2.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
  ) AS ActiveLast30Days,
  /* Hot questions without accepted answers */
  (SELECT count(*) FROM Posts p2 WHERE p2.OwnerUserId = ru.UserId AND p2.PostTypeId=1 AND COALESCE(p2.ViewCount,0) > 10000 AND (p2.AcceptedAnswerId IS NULL)) AS HotUnacceptedQuestions,
  /* Vote types they cast */
  (SELECT string_agg(vt.Name || ':' || cnt, ', ' ORDER BY cnt DESC)
   FROM (
     SELECT vt.Name, count(*) AS cnt FROM Votes v
     JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
     WHERE v.UserId = ru.UserId
     GROUP BY vt.Name
   ) vt
  ) AS VoteTypesCastSummary,
  dense_rank() OVER (ORDER BY CASE WHEN (COALESCE(ru.Questions,0)+COALESCE(ru.Answers,0))=0 THEN NULL ELSE (ru.Reputation::numeric / NULLIF((COALESCE(ru.Questions,0)+COALESCE(ru.Answers,0)),0)) END DESC NULLS LAST) AS RepPerContributionRank
FROM ranked_users ru
LEFT JOIN badge_summary bs ON bs.UserId = ru.UserId
LEFT JOIN vote_summary vs ON vs.UserId = ru.UserId
LEFT JOIN link_summary ls ON ls.UserId = ru.UserId
WHERE (ru.Reputation > 1000 OR ru.EngagementRank <= 100)
ORDER BY ru.EngagementRank, ru.Reputation DESC
LIMIT 250;