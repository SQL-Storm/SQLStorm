WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVoteGiven,
           (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVoteGiven
    FROM Users u
),
RankedUsers AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.NetVotes,
           us.GoldBadges,
           us.SilverBadges,
           us.BronzeBadges,
           us.QuestionCount,
           us.AnswerCount,
           us.UpVoteGiven,
           us.DownVoteGiven,
           ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC) AS RepRank,
           RANK() OVER (ORDER BY (us.GoldBadges * 100 + us.SilverBadges * 10 + us.BronzeBadges) DESC) AS BadgeRank
    FROM UserStats us
),
LastPostInfo AS (
    SELECT p.OwnerUserId,
           MAX(p.CreationDate) AS LastPostDate,
           COUNT(CASE WHEN p.Score > 0 THEN 1 END) AS PositiveScorePosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RelevantTags AS (
    SELECT p.OwnerUserId,
           -- STRING_AGG may be different per dialect; use array_agg + string join for portability if needed.
           STRING_AGG(t.TagName, ', ') AS TagList
    FROM Tags t
    JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
    WHERE t.TagName IS NOT NULL
    GROUP BY p.OwnerUserId
),
InactiveUsers AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           0 AS NetVotes,
           0 AS GoldBadges,
           0 AS SilverBadges,
           0 AS BronzeBadges,
           0 AS QuestionCount,
           0 AS AnswerCount,
           0 AS UpVoteGiven,
           0 AS DownVoteGiven,
           'Inactive' AS ReputationTier,
           CAST(NULL AS TIMESTAMP) AS LastPostDate,
           CAST(NULL AS VARCHAR) AS TagList
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
)

SELECT ru.Id,
       ru.DisplayName,
       ru.Reputation,
       ru.NetVotes,
       ru.GoldBadges,
       ru.SilverBadges,
       ru.BronzeBadges,
       ru.QuestionCount,
       ru.AnswerCount,
       ru.UpVoteGiven,
       ru.DownVoteGiven,
       CASE
           WHEN ru.Reputation IS NULL THEN 'No Rep'
           WHEN ru.Reputation < 1000 THEN 'Newbie'
           WHEN ru.Reputation < 10000 THEN 'Experienced'
           ELSE 'Veteran'
       END AS ReputationTier,
       lp.LastPostDate,
       lp.PositiveScorePosts,
       COALESCE(rt.TagList, '') AS RelevantTags
FROM RankedUsers ru
LEFT JOIN LastPostInfo lp ON lp.OwnerUserId = ru.Id
LEFT JOIN RelevantTags rt ON rt.OwnerUserId = ru.Id
WHERE ru.RepRank <= 100

UNION ALL

SELECT iu.Id,
       iu.DisplayName,
       iu.Reputation,
       iu.NetVotes,
       iu.GoldBadges,
       iu.SilverBadges,
       iu.BronzeBadges,
       iu.QuestionCount,
       iu.AnswerCount,
       iu.UpVoteGiven,
       iu.DownVoteGiven,
       iu.ReputationTier,
       iu.LastPostDate,
       0 AS PositiveScorePosts,
       iu.TagList
FROM InactiveUsers iu
WHERE iu.Reputation IS NOT NULL

ORDER BY Reputation DESC NULLS LAST, Id;