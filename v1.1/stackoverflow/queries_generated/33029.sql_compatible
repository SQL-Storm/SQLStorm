WITH TopTags AS (
    SELECT 
        t.TagName,
        COUNT(*) AS TagUsageCount,
        AVG(p.Score) AS AverageScorePerPost,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthorCount
    FROM 
        Tags t
        JOIN Posts p ON CAST(t.Id AS INTEGER) = CAST(p.Tags AS INTEGER)
    GROUP BY 
        t.TagName
), 
ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS QuestionsCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        AVG(p.Score) AS AveragePostScore
    FROM 
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
    GROUP BY 
        u.Id, u.DisplayName
),
PostHistoryAnalysis AS (
    SELECT 
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 END) AS ClosureReopenEvents
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
),
VoteStatistics AS (
    SELECT 
        v.VoteTypeId,
        COUNT(*) AS VoteCount
    FROM 
        Votes v
    GROUP BY 
        v.VoteTypeId
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsMade,
        COUNT(c.Id) AS CommentsMade,
        COUNT(v.Id) AS VotesCast
    FROM 
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Comments c ON u.Id = c.UserId
        LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    tt.TagName,
    tt.TagUsageCount,
    tt.AverageScorePerPost,
    tt.UniqueAuthorCount,
    AU.UserId,
    AU.DisplayName,
    AU.QuestionsCount,
    AU.AnswersCount,
    AU.AveragePostScore,
    PA.TitleEdits,
    PA.BodyEdits,
    PA.ClosureReopenEvents,
    VS.VoteCount,
    VS.VoteTypeId,
    UA.PostsMade,
    UA.CommentsMade,
    UA.VotesCast
FROM 
    TopTags tt
    LEFT JOIN ActiveUsers AU ON 1=1
    LEFT JOIN PostHistoryAnalysis PA ON 1=1
    LEFT JOIN VoteStatistics VS ON 1=1
    LEFT JOIN UserActivity UA ON 1=1
ORDER BY 
    tt.TagUsageCount DESC
LIMIT 100;