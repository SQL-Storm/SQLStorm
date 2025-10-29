WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.Tags, '') AS CleanTags,
        COALESCE(p.Title, '') AS CleanTitle,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS GlobalPostSeq,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        COALESCE(
            LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate),
            0
        ) AS PrevScoreByUser,
        COALESCE(
            LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate),
            p.CreationDate
        ) AS PrevCreationDateByUser,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        COUNT(DISTINCT ps.PostId) AS TotalPosts,
        COALESCE(SUM(ps.Score), 0) AS TotalScore,
        COALESCE(AVG(ps.Score), 0) AS AvgScore,
        COALESCE(MAX(ps.Score), 0) AS MaxScore,
        COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN ps.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        COUNT(DISTINCT ps.ParentId) AS AnsweredQuestions,
        AVG(COALESCE(ps.Score, 0) * COALESCE(ps.ViewCount, 1)) AS ScorePerView,
        COUNT(DISTINCT ps.Tags) AS TagVariety
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY 
        u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
RankedUsers AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.DisplayName,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.LastAccessDate,
        ua.TotalPosts,
        ua.TotalScore,
        ua.AvgScore,
        ua.MaxScore,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AnsweredQuestions,
        ua.ScorePerView,
        ua.TagVariety,
        RANK() OVER (ORDER BY ua.TotalScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY ua.Reputation DESC) AS RepRank,
        CASE 
            WHEN ua.TotalPosts > 50 THEN 'HighlyActive'
            WHEN ua.TotalPosts > 20 THEN 'Active'
            ELSE 'Regular'
        END AS ActivityLevel
    FROM UserActivity ua
),
TagAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Tags,
        COALESCE(p.Tags, '') AS CleanTags,
        LENGTH(COALESCE(p.Tags, '')) - LENGTH(REPLACE(COALESCE(p.Tags, ''), '>', '')) AS TagCount,
        -- use a generic split function: STRING_TO_ARRAY is Postgres; for portability leave as is but avoid :: casts
        STRING_TO_ARRAY(SUBSTRING(COALESCE(p.Tags, ''), 2, GREATEST(LENGTH(COALESCE(p.Tags, '')) - 2, 0)), '><') AS TagArray,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Posts p2 
             WHERE p2.Tags LIKE '%' || p.Tags || '%' 
               AND p2.Id != p.Id 
               AND p2.PostTypeId = 1
            ),
            0
        ) AS DuplicateTagPosts,
        COALESCE(
            (SELECT COUNT(DISTINCT ph.UserId) 
             FROM PostHistory ph 
             WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
            ),
            0
        ) AS EditorCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
ComplexPostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.PostType,
        ps.ScoreCategory,
        ps.GlobalPostSeq,
        ps.UserPostRank,
        ps.DaysSinceCreation,
        ps.Score - ps.PrevScoreByUser AS ScoreChange,
        CAST(EXTRACT(EPOCH FROM (ps.CreationDate - ps.PrevCreationDateByUser)) / 86400 AS INTEGER) AS DaysBetweenPosts,
        CASE 
            WHEN ps.Score >= 100 THEN 100
            WHEN ps.Score >= 50 THEN 50
            ELSE 0
        END AS ScorePoint,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = ps.PostId
            ),
            0
        ) AS CommentCountFromCommentsTable,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = ps.PostId
               AND v.VoteTypeId = 2
            ),
            0
        ) AS UpvoteCount,
        CASE 
            WHEN ps.Score < 0 THEN 'Negative'
            WHEN ps.Score = 0 THEN 'Zero'
            WHEN ps.Score BETWEEN 1 AND 10 THEN 'Low'
            WHEN ps.Score BETWEEN 11 AND 50 THEN 'Medium'
            WHEN ps.Score > 50 THEN 'High'
            ELSE 'Unknown'
        END AS ScoreTier
    FROM PostStats ps
),
CombinedResults AS (
    SELECT 
        ps.PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        ps.PostType,
        ps.ScoreCategory,
        ps.GlobalPostSeq,
        ps.UserPostRank,
        ps.DaysSinceCreation,
        ps.Score - ps.PrevScoreByUser AS ScoreChange,
        CAST(EXTRACT(EPOCH FROM (ps.CreationDate - ps.PrevCreationDateByUser)) / 86400 AS INTEGER) AS DaysBetweenPosts,
        ru.TotalPosts,
        ru.TotalScore,
        ru.Reputation,
        ru.DisplayName,
        ru.Views,
        ru.UpVotes,
        ru.DownVotes,
        ru.LastAccessDate,
        CASE 
            WHEN ps.Score >= 100 THEN 'HighValue'
            WHEN ps.Score >= 50 THEN 'MediumValue'
            ELSE 'LowValue'
        END AS ValueCategory,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 1
            ELSE 0
        END AS HasAnswers,
        CASE 
            WHEN ps.CommentCount > 0 THEN 1
            ELSE 0
        END AS HasComments,
        CASE 
            WHEN ps.FavoriteCount > 0 THEN 1
            ELSE 0
        END AS Favorited,
        COALESCE(ta.DuplicateTagPosts, 0) AS DuplicateTagPosts,
        COALESCE(ta.EditorCount, 0) AS EditorCount,
        COALESCE(pa.CommentCountFromCommentsTable, 0) AS CommentCountFromCommentsTable,
        COALESCE(pa.UpvoteCount, 0) AS UpvoteCount,
        pa.ScoreTier,
        ru.ScoreRank,
        ru.RepRank,
        ru.ActivityLevel,
        ru.TagVariety,
        ps.GlobalPostSeq AS GlobalPostSeq_For_Order
    FROM PostStats ps
    INNER JOIN RankedUsers ru ON ps.OwnerUserId = ru.UserId
    LEFT JOIN TagAnalysis ta ON ps.PostId = ta.PostId
    LEFT JOIN ComplexPostAnalysis pa ON ps.PostId = pa.PostId
    WHERE ps.PostId IN (
        SELECT ps2.PostId 
        FROM PostStats ps2 
        WHERE ps2.Score > 0 
          AND ps2.AnswerCount > 0 
          AND ps2.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
    )
)
SELECT 
    PostId,
    OwnerUserId,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    Title,
    Tags,
    PostType,
    ScoreCategory,
    TotalPosts,
    TotalScore,
    Reputation,
    DisplayName,
    ValueCategory,
    HasAnswers,
    HasComments,
    Favorited,
    DuplicateTagPosts,
    EditorCount,
    CommentCountFromCommentsTable,
    UpvoteCount,
    ScoreTier,
    ScoreRank,
    RepRank,
    ActivityLevel,
    TagVariety,
    CASE 
        WHEN (CAST(Score AS DECIMAL) / NULLIF(ViewCount, 0)) > 1.0 THEN 'High Engagement'
        WHEN (CAST(Score AS DECIMAL) / NULLIF(ViewCount, 0)) > 0.5 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel
FROM CombinedResults
WHERE (Score > 0) 
  AND (TotalScore > 1000)
  AND (Reputation > 2000)
  AND (DaysSinceCreation < 365)
  AND (CASE 
        WHEN TagVariety > 3 THEN 1
        ELSE 0
       END = 1)
ORDER BY Score DESC, TotalScore DESC, RepRank ASC, GlobalPostSeq_For_Order DESC
LIMIT 500;