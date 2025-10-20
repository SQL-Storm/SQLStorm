WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(p.Id) AS TotalPosts,
           AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
           AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserActivity AS (
    SELECT v.UserId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCast,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesCast,
           COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesCast,
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
       ROUND(CAST(ru.AvgQuestionScore AS DECIMAL), 2) AS AvgQuestionScore,
       ROUND(CAST(ru.AvgAnswerScore AS DECIMAL), 2) AS AvgAnswerScore,
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
LEFT JOIN (
    SELECT p_inner.Id AS PostId,
           TRIM(tag) AS tag
    FROM Posts p_inner,
         LATERAL (
             SELECT UNNEST(string_to_array(SUBSTRING(p_inner.Tags FROM 2 FOR (LENGTH(p_inner.Tags) - 2)), '><')) AS tag
         ) s
    WHERE p_inner.PostTypeId = 1
) pt ON pt.PostId = p.Id
LEFT JOIN Tags t ON t.TagName = pt.tag
WHERE ru.RepRank <= 100
GROUP BY ru.Id, ru.DisplayName, ru.Reputation, ru.GoldBadges, ru.TotalPosts,
         ru.AvgQuestionScore, ru.AvgAnswerScore, ru.LastPostDate,
         ru.UpVotesCast, ru.DownVotesCast, ru.FavoritesCast, ru.LastVoteDate,
         ru.RepRank
ORDER BY ru.RepRank;