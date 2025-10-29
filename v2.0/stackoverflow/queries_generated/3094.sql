-- {"query": "3094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2439} 

WITH user_posts AS (
    SELECT u.Id AS UserId,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           SUM(p.Score) AS TotalScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
user_votes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE vt.Id = 2) AS UpVoteCount,
           COUNT(*) FILTER (WHERE vt.Id = 3) AS DownVoteCount,
           SUM(CASE WHEN vt.Id = 2 THEN 1 WHEN vt.Id = 3 THEN -1 ELSE 0 END) AS VoteScore
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),
user_badges AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount,
           STRING_AGG(DISTINCT b.Name, ',') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
user_top_tag AS (
    SELECT p.OwnerUserId AS UserId,
           t.TagName,
           cnt,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY cnt DESC) AS rn
    FROM (
        SELECT OwnerUserId,
               UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM Tags), '><')) AS TagName,
               COUNT(*) AS cnt
        FROM Posts
        WHERE OwnerUserId IS NOT NULL AND PostTypeId = 1
        GROUP BY OwnerUserId, TagName
    ) p
    JOIN Tags t ON t.TagName = p.TagName
),
user_recent_activity AS (
    SELECT u.Id AS UserId,
           GREATEST(
               COALESCE(u.LastAccessDate, '1970-01-01'::timestamp),
               COALESCE(p.LastActivityDate, '1970-01-01'::timestamp),
               COALESCE(c.CreationDate, '1970-01-01'::timestamp)
           ) AS RecentActivityTs
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
),
combined AS (
    SELECT u.Id,
           u.DisplayName,
           COALESCE(up.QuestionCount,0) AS QuestionCount,
           COALESCE(up.AnswerCount,0) AS AnswerCount,
           COALESCE(up.TotalScore,0) AS TotalScore,
           COALESCE(v.UpVoteCount,0) AS UpVoteCount,
           COALESCE(v.DownVoteCount,0) AS DownVoteCount,
           COALESCE(v.VoteScore,0) AS VoteScore,
           COALESCE(b.GoldBadgeCount,0) AS GoldBadgeCount,
           COALESCE(b.SilverBadgeCount,0) AS SilverBadgeCount,
           COALESCE(b.BronzeBadgeCount,0) AS BronzeBadgeCount,
           b.BadgeList,
           t.TagName AS TopTag,
           t.cnt     AS TopTagCount,
           ra.RecentActivityTs,
           /* Composite benchmark score */
           (u.Reputation * 0.4
            + COALESCE(up.TotalScore,0) * 0.2
            + COALESCE(v.VoteScore,0) * 0.15
            + (COALESCE(b.GoldBadgeCount,0)*5
               + COALESCE(b.SilverBadgeCount,0)*3
               + COALESCE(b.BronzeBadgeCount,0)) * 0.1
            + COALESCE(t.cnt,0) * 0.05) AS BenchmarkScore
    FROM Users u
    LEFT JOIN user_posts up          ON up.UserId = u.Id
    LEFT JOIN user_votes v          ON v.UserId = u.Id
    LEFT JOIN user_badges b         ON b.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, TagName, cnt
        FROM user_top_tag
        WHERE rn = 1
    ) t                           ON t.UserId = u.Id
    LEFT JOIN user_recent_activity ra ON ra.UserId = u.Id
)
SELECT *
FROM combined
WHERE BenchmarkScore IS NOT NULL
ORDER BY BenchmarkScore DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT NULL AS Id,
       '--- Summary ---' AS DisplayName,
       NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL,
       NULL,
       NULL, NULL,
       MAX(RecentActivityTs) AS MostRecentActivity,
       AVG(BenchmarkScore) AS AvgBenchmarkScore
FROM combined;
