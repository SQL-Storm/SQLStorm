WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           COALESCE(u.Location, 'Unknown') AS Location,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalPosts,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
           (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
              FROM Votes v
              WHERE v.UserId = u.Id) AS UpVoteGiven,
           (SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
              FROM Votes v
              WHERE v.UserId = u.Id) AS DownVoteGiven
    FROM Users u
),
TagUsage AS (
    SELECT t.TagName,
           COUNT(p.Id) AS QuestionUses,
           SUM(p.Score) AS TotalScore,
           ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
TopTags AS (
    SELECT TagName, QuestionUses, TotalScore
    FROM TagUsage
    WHERE TagRank <= 10
),
PostActivity AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.PostTypeId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.FavoriteCount,
           COALESCE(p.ClosedDate, p.CreationDate) AS EffectiveDate,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
           CASE
               WHEN p.Score > COALESCE(LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate),0) THEN 1
               ELSE 0
           END AS ScoreImproved
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserRankings AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.TotalPosts,
           us.QuestionCount,
           us.AnswerCount,
           us.BadgeCount,
           us.UpVoteGiven,
           us.DownVoteGiven,
           RANK() OVER (ORDER BY us.Reputation DESC, us.TotalPosts DESC) AS ReputationRank,
           ROW_NUMBER() OVER (ORDER BY (us.AnswerCount*2 + us.QuestionCount) DESC) AS ActivityRank
    FROM UserStats us
),
LatestPerUser AS (
    SELECT p.OwnerUserId,
           p.Score,
           p.ViewCount,
           p.FavoriteCount,
           p.ScoreImproved,
           p.CreationDate
    FROM PostActivity p
),
MaxTagPerUser AS (
    SELECT OwnerUserId, MAX(QuestionUses) AS MaxUses
    FROM (
        SELECT p.OwnerUserId,
               t.TagName,
               COUNT(*) AS QuestionUses
        FROM Posts p
        JOIN Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
        WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, t.TagName
    ) uq
    GROUP BY OwnerUserId
)
SELECT ur.Id,
       ur.DisplayName,
       ur.Reputation,
       ur.TotalPosts,
       ur.QuestionCount,
       ur.AnswerCount,
       ur.BadgeCount,
       ur.UpVoteGiven,
       ur.DownVoteGiven,
       ur.ReputationRank,
       ur.ActivityRank,
       COALESCE(tt.TagName,'None') AS TopTag,
       COALESCE(tt.QuestionUses,0) AS TagQuestionUses,
       COALESCE(tt.TotalScore,0) AS TagTotalScore,
       pa.Score,
       pa.ViewCount,
       pa.FavoriteCount,
       pa.ScoreImproved,
       CASE WHEN pa.ScoreImproved = 1 THEN 'Improving' ELSE 'Stagnant' END AS ScoreTrend
FROM UserRankings ur
LEFT JOIN MaxTagPerUser mu ON mu.OwnerUserId = ur.Id
LEFT JOIN TopTags tt ON tt.QuestionUses = mu.MaxUses
LEFT JOIN LATERAL (
    SELECT p.Score,
           p.ViewCount,
           p.FavoriteCount,
           p.ScoreImproved,
           p.CreationDate
    FROM LatestPerUser p
    WHERE p.OwnerUserId = ur.Id
    ORDER BY p.CreationDate DESC
    LIMIT 1
) pa ON TRUE
WHERE ur.ReputationRank <= 100

UNION ALL

SELECT CAST(NULL AS INTEGER) AS Id,
       'Aggregate' AS DisplayName,
       CAST(NULL AS INTEGER) AS Reputation,
       SUM(ur.TotalPosts) AS TotalPosts,
       SUM(ur.QuestionCount) AS QuestionCount,
       SUM(ur.AnswerCount) AS AnswerCount,
       SUM(ur.BadgeCount) AS BadgeCount,
       SUM(ur.UpVoteGiven) AS UpVoteGiven,
       SUM(ur.DownVoteGiven) AS DownVoteGiven,
       CAST(NULL AS INTEGER) AS ReputationRank,
       CAST(NULL AS INTEGER) AS ActivityRank,
       CAST(NULL AS VARCHAR) AS TopTag,
       CAST(NULL AS INTEGER) AS TagQuestionUses,
       CAST(NULL AS BIGINT) AS TagTotalScore,
       CAST(NULL AS INTEGER) AS Score,
       CAST(NULL AS INTEGER) AS ViewCount,
       CAST(NULL AS INTEGER) AS FavoriteCount,
       CAST(NULL AS INTEGER) AS ScoreImproved,
       CAST(NULL AS VARCHAR) AS ScoreTrend
FROM UserRankings ur
WHERE ur.ReputationRank <= 100

ORDER BY ReputationRank ASC
LIMIT 200;