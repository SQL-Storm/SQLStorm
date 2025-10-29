-- {"query": "3941.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2145} 

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
    FROM Users u
    WHERE u.Reputation > 1000
),
PostAgg AS (
    SELECT p.OwnerUserId                                                AS UserId,
           COUNT(*)                                                    AS TotalPosts,
           AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)            AS AvgScore,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)          AS Questions,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)          AS Answers,
           MAX(p.CreationDate)                                        AS LastPostDate,
           STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '><'))), ',')
                                                                     AS AllTags
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
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
           pa.TotalPosts,
           pa.AvgScore,
           pa.Questions,
           pa.Answers,
           pa.LastPostDate,
           pa.AllTags,
           ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC) AS ReputationRank,
           RANK()       OVER (ORDER BY pa.AvgScore DESC NULLS LAST)          AS ScoreRank
    FROM UserStats us
    LEFT JOIN PostAgg pa ON pa.UserId = us.Id
),
TagAnalytics AS (
    SELECT t.TagName,
           COUNT(p.Id)                                            AS TaggedPosts,
           SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END)           AS PositiveScorePosts,
           AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)       AS AvgTagScore,
           MAX(p.CreationDate)                                   AS MostRecentPost
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%'||t.TagName||'%'
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),
TopTags AS (
    SELECT TagName,
           TaggedPosts,
           AvgTagScore,
           ROW_NUMBER() OVER (ORDER BY TaggedPosts DESC) AS TagRank
    FROM TagAnalytics
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
       ru.TotalPosts,
       ru.AvgScore,
       ru.ReputationRank,
       ru.ScoreRank,
       COALESCE(tt.TagName, 'N/A')        AS PopularTag,
       COALESCE(tt.TaggedPosts,0)         AS TagPostCount,
       COALESCE(tt.AvgTagScore,0)         AS TagAvgScore
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT t.TagName, t.TaggedPosts, t.AvgTagScore
    FROM TopTags t
    WHERE t.TagRank <= 5
    ORDER BY POSITION(t.TagName IN COALESCE(ru.AllTags,'')) ASC NULLS LAST
    LIMIT 1
) tt ON TRUE
WHERE ru.ReputationRank <= 50

UNION ALL

SELECT NULL AS Id,
       '--- Summary ---' AS DisplayName,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL,
       (SELECT SUM(TotalPosts) FROM RankedUsers) AS TotalPostsAll,
       (SELECT AVG(AvgScore) FROM RankedUsers)   AS AvgScoreAll,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL
FROM (SELECT 1) s
ORDER BY ReputationRank NULLS LAST, Id;
