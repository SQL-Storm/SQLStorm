-- {"query": "55009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1507} 

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(p.Id) AS TotalPosts,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserActivity AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesCast,
           MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.UserId
),
RankedUsers AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.GoldBadges,
           us.TotalPosts,
           us.AvgQuestionScore,
           us.AvgAnswerScore,
           us.LastPostDate,
           ua.UpVotesCast,
           ua.DownVotesCast,
           ua.FavoritesCast,
           ua.LastVoteDate,
           ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.GoldBadges DESC) AS RepRank
    FROM UserStats us
    LEFT JOIN UserActivity ua ON ua.UserId = us.Id
)
SELECT ru.Id,
       ru.DisplayName,
       ru.Reputation,
       ru.GoldBadges,
       ru.TotalPosts,
       ROUND(ru.AvgQuestionScore::numeric, 2) AS AvgQuestionScore,
       ROUND(ru.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
       ru.LastPostDate,
       ru.UpVotesCast,
       ru.DownVotesCast,
       ru.FavoritesCast,
       ru.LastVoteDate,
       ru.RepRank,
       ARRAY_AGG(t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TopTags
FROM RankedUsers ru
LEFT JOIN Posts p
       ON p.OwnerUserId = ru.Id AND p.PostTypeId = 1
LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
) AS pt(tag) ON true
LEFT JOIN Tags t ON t.TagName = pt.tag
WHERE ru.RepRank <= 100
GROUP BY ru.Id, ru.DisplayName, ru.Reputation, ru.GoldBadges, ru.TotalPosts,
         ru.AvgQuestionScore, ru.AvgAnswerScore, ru.LastPostDate,
         ru.UpVotesCast, ru.DownVotesCast, ru.FavoritesCast, ru.LastVoteDate,
         ru.RepRank
ORDER BY ru.RepRank;
