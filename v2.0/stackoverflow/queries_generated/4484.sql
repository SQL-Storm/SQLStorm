-- {"query": "4484.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1098} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(p.Id) DESC) AS RankByReputationAndActivity
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE u.CreationDate < DATE('now', '-1 year')
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        pt.Name AS PostType,
        TAGS.TagName,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        LEVENSHTEIN(SUBSTRING(p.Body, 1, 500), LOWER(COALESCE(p.Title, ''))) AS TitleBodySimilarity,
        CASE
            WHEN LENGTH(p.Body) > 1000 AND p.AnswerCount > 5 THEN 1
            ELSE 0
        END AS IsComplexOrPopular
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT
            posts.Id AS PostId,
            tags.TagName
        FROM Posts posts
        CROSS APPLY string_to_array(SUBSTRING(posts.Tags, 2, LENGTH(posts.Tags) - 2), '><') AS tag_list
        CROSS APPLY UNNEST(tag_list) AS tags(TagName)
        WHERE posts.Tags IS NOT NULL AND posts.PostTypeId = 1
    ) AS TAGS ON p.Id = TAGS.PostId
    WHERE p.CreationDate > DATE('now', '-6 months')
),
UserPostInteraction AS (
    SELECT
        p.OwnerUserId,
        COUNT(c.Id) AS CommentCountForUserPosts,
        AVG(c.Score) AS AvgCommentScoreForUserPosts
    FROM Posts p
    JOIN Comments c ON p.Id = c.PostId
    WHERE c.CreationDate > DATE('now', '-3 months')
    GROUP BY p.OwnerUserId
)
SELECT
    rua.DisplayName,
    rua.Reputation,
    rua.PostCount,
    rua.QuestionCount,
    rua.AnswerCount,
    pca.Title,
    pca.PostType,
    pca.TagName,
    pca.PostStatus,
    pca.TitleBodySimilarity,
    pca.IsComplexOrPopular,
    upi.CommentCountForUserPosts,
    upi.AvgCommentScoreForUserPosts,
    CASE
        WHEN rua.RankByReputationAndActivity <= 100 THEN 'Top 100'
        WHEN rua.RankByReputationAndActivity <= 500 THEN 'Top 500'
        ELSE 'Other'
    END AS UserTier,
    CASE
        WHEN pca.Score > 50 AND pca.ViewCount > 10000 THEN 'High Impact'
        WHEN pca.Score < 0 OR pca.ViewCount < 100 THEN 'Low Engagement'
        ELSE 'Moderate Engagement'
    END AS PostEngagementLevel,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS UserWebsiteStatus,
    CAST(SUBSTRING(u.AboutMe, 1, 100) AS VARCHAR(100)) AS AboutMeSnippet
FROM RankedUserActivity rua
JOIN UserPostInteraction upi ON rua.UserId = upi.OwnerUserId
LEFT JOIN Posts pca ON rua.UserId = pca.OwnerUserId
LEFT JOIN Users u ON rua.UserId = u.Id
WHERE pca.PostId IS NOT NULL
  AND (pca.Score > 0 OR pca.AnswerCount > 0)
  AND (upi.CommentCountForUserPosts > 0 OR upi.AvgCommentScoreForUserPosts IS NOT NULL)
  AND (pca.IsComplexOrPopular = 1 OR rua.RankByReputationAndActivity <= 100)
ORDER BY rua.Reputation DESC, pca.Score DESC
LIMIT 100;
