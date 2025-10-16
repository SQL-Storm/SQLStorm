-- {"query": "22035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1021} 

WITH UserBadgeSummary AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COALESCE(b.GoldBadges, 0) AS GoldBadges,
           COALESCE(b.SilverBadges, 0) AS SilverBadges,
           COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
           CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE LEFT(u.Location, 50) END AS LocationShort,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.CreationDate < '2019-01-01'
),
UserPostStats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) AS TotalPosts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
           AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgScore,
           STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS TopTags
    FROM Posts p
    LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name ON TRUE
    LEFT JOIN Tags t ON t.TagName = tag_name
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteStats AS (
    SELECT v.UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
           COUNT(CASE WHEN v.VoteTypeId IN (4, 12) THEN 1 END) AS NegativeVotes
    FROM Votes v
    GROUP BY v.UserId
),
RankedUsers AS (
    SELECT ubs.*,
           ups.TotalPosts,
           ups.QuestionsCount,
           ups.AnswersCount,
           ups.AvgScore,
           ups.TopTags,
           uvs.UpVotesReceived,
           uvs.DownVotesReceived,
           uvs.NegativeVotes,
           (ubs.GoldBadges * 10 + ubs.SilverBadges * 5 + ubs.BronzeBadges) +
           COALESCE(ups.AvgScore, 0) +
           COALESCE(uvs.UpVotesReceived - uvs.DownVotesReceived, 0) AS CompositeScore,
           ROW_NUMBER() OVER (ORDER BY (ubs.GoldBadges * 10 + ubs.SilverBadges * 5 + ubs.BronzeBadges) +
                                        COALESCE(ups.AvgScore, 0) +
                                        COALESCE(uvs.UpVotesReceived - uvs.DownVotesReceived, 0) DESC) AS OverallRank
    FROM UserBadgeSummary ubs
    LEFT JOIN UserPostStats ups ON ubs.UserId = ups.UserId
    LEFT JOIN UserVoteStats uvs ON ubs.UserId = uvs.UserId
)
SELECT ru.UserId,
       ru.DisplayName,
       ru.Reputation,
       ru.GoldBadges,
       ru.SilverBadges,
       ru.BronzeBadges,
       ru.LocationShort,
       ru.ReputationRank,
       ru.TotalPosts,
       ru.QuestionsCount,
       ru.AnswersCount,
       ru.AvgScore,
       ru.TopTags,
       ru.UpVotesReceived,
       ru.DownVotesReceived,
       ru.NegativeVotes,
       ru.CompositeScore,
       ru.OverallRank,
       CASE WHEN ru.AnswersCount > ru.QuestionsCount THEN 'Answerer' ELSE 'Questioner' END AS UserType
FROM RankedUsers ru
WHERE ru.OverallRank <= 100
  AND ru.GoldBadges + ru.SilverBadges + ru.BronzeBadges > 0
  AND NOT EXISTS (
      SELECT 1 FROM Comments c
      WHERE c.UserId = ru.UserId
      AND c.Score < 0
      GROUP BY c.UserId
      HAVING COUNT(*) > 10
  )
ORDER BY ru.OverallRank ASC, ru.Reputation DESC;
