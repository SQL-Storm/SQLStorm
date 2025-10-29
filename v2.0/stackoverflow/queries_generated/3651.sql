-- {"query": "3651.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2123} 

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Views,0)                                        AS TotalViews,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id)   AS CommentCount,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id)     AS BadgeCount,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount
    FROM Users u
),

TagAgg AS (
    SELECT p.OwnerUserId AS UserId,
           UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag,
           COUNT(*)                                                   AS TagUseCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL
      AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId, Tag
),

UserTopTags AS (
    SELECT t.UserId,
           STRING_AGG(t.Tag, ', ') FILTER (WHERE t.rn <= 3) AS TopTags
    FROM (
        SELECT ta.UserId,
               ta.Tag,
               ta.TagUseCount,
               ROW_NUMBER() OVER (PARTITION BY ta.UserId ORDER BY ta.TagUseCount DESC) AS rn
        FROM TagAgg ta
    ) t
    GROUP BY t.UserId
),

RecentActivity AS (
    SELECT u.Id                                            AS UserId,
           GREATEST(MAX(p.LastActivityDate), MAX(p.CreationDate)) AS LastPostActivity,
           MAX(c.CreationDate)                                   AS LastCommentActivity
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId     = u.Id
    GROUP BY u.Id
),

VoteStats AS (
    SELECT p.OwnerUserId                                      AS UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)  AS UpVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)  AS DownVotesReceived,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY v.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

UserRankings AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.TotalViews,
           us.PostCount,
           us.QuestionCount,
           us.AnswerCount,
           us.CommentCount,
           us.BadgeCount,
           us.GoldBadgeCount,
           COALESCE(ut.TopTags,'')                           AS TopTags,
           ra.LastPostActivity,
           ra.LastCommentActivity,
           vs.UpVotesReceived,
           vs.DownVotesReceived,
           DENSE_RANK() OVER (ORDER BY us.Reputation DESC)   AS ReputationRank,
           DENSE_RANK() OVER (ORDER BY us.PostCount DESC)   AS PostCountRank
    FROM UserStats      us
    LEFT JOIN UserTopTags    ut ON ut.UserId = us.Id
    LEFT JOIN RecentActivity ra ON ra.UserId = us.Id
    LEFT JOIN VoteStats      vs ON vs.UserId = us.Id AND vs.rn = 1
    WHERE us.Reputation > 0
      AND (us.PostCount > 0 OR us.BadgeCount > 0)
)

SELECT *
FROM UserRankings
WHERE ReputationRank <= 100
   OR PostCountRank <= 100
ORDER BY ReputationRank, PostCountRank
UNION ALL
SELECT NULL AS Id,
       '--- Summary ---' AS DisplayName,
       NULL AS Reputation,
       NULL AS TotalViews,
       NULL AS PostCount,
       NULL AS QuestionCount,
       NULL AS AnswerCount,
       NULL AS CommentCount,
       NULL AS BadgeCount,
       NULL AS GoldBadgeCount,
       NULL AS TopTags,
       MAX(ra.LastPostActivity)   AS LastPostActivity,
       MAX(ra.LastCommentActivity) AS LastCommentActivity,
       SUM(vs.UpVotesReceived)    AS UpVotesReceived,
       SUM(vs.DownVotesReceived)  AS DownVotesReceived,
       NULL AS ReputationRank,
       NULL AS PostCountRank
FROM RecentActivity ra
LEFT JOIN VoteStats vs ON vs.UserId = ra.UserId
GROUP BY ()
HAVING COUNT(*) > 0;
