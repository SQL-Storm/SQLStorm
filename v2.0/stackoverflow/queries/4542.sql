-- {"query": "4542.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1482}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 10
),
CommentDetails AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS NumberOfComments,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreFromPosts,
        AVG(CAST(p.AnswerCount AS DOUBLE PRECISION)) AS AvgAnswersPerQuestion,
        COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT
        UserId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        COUNT(Id) AS TotalVotesCast
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY UserId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.TagName NOT LIKE '%[^a-zA-Z0-9-]%' -- Filter for common tag name patterns
),
PostLaggedScore AS (
    SELECT
        PostId,
        PostScore,
        LAG(PostScore, 1, 0) OVER (PARTITION BY OwnerUserId ORDER BY PostCreationDate) AS PreviousPostScore
    FROM RankedPosts
),
PostRankedCommentScore AS (
    SELECT
        PostId,
        TotalCommentScore,
        RANK() OVER (ORDER BY TotalCommentScore DESC) AS CommentScoreRank
    FROM CommentDetails
),
CombinedData AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.PostCreationDate,
        rp.PostScore,
        rp.AnswerCount,
        rp.CommentCount,
        cd.NumberOfComments,
        cd.TotalCommentScore,
        cd.LastCommentDate,
        upa.TotalPostsOwned,
        upa.TotalScoreFromPosts,
        upa.AvgAnswersPerQuestion,
        upa.ClosedQuestions,
        pls.PreviousPostScore,
        prcs.CommentScoreRank,
        CASE
            WHEN rp.PostScore > 100 THEN 'High'
            WHEN rp.PostScore > 20 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        UPPER(SUBSTRING(rp.Title FROM 1 FOR 3)) AS TitlePrefix,
        CASE
            WHEN rp.PostCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Old'
            ELSE 'Recent'
        END AS AgeCategory,
        CASE
            WHEN cd.NumberOfComments > 50 THEN 'High'
            WHEN cd.NumberOfComments > 10 THEN 'Medium'
            ELSE 'Low'
        END AS CommentVolumeCategory,
        rp.PostScore - COALESCE(pls.PreviousPostScore, 0) AS ScoreDifferenceFromPrevious,
        rp.rn
    FROM RankedPosts rp
    LEFT JOIN CommentDetails cd ON rp.PostId = cd.PostId
    LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.OwnerUserId
    LEFT JOIN PostLaggedScore pls ON rp.PostId = pls.PostId
    LEFT JOIN PostRankedCommentScore prcs ON rp.PostId = prcs.PostId
)
SELECT
    cd.PostId,
    cd.Title,
    cd.OwnerUserId,
    cd.OwnerDisplayName,
    cd.PostCreationDate,
    cd.PostScore,
    cd.AnswerCount,
    cd.CommentCount,
    cd.NumberOfComments,
    cd.TotalCommentScore,
    cd.LastCommentDate,
    cd.TotalPostsOwned,
    cd.TotalScoreFromPosts,
    cd.AvgAnswersPerQuestion,
    cd.ClosedQuestions,
    cd.PreviousPostScore,
    cd.CommentScoreRank,
    cd.ScoreCategory,
    cd.TitlePrefix,
    cd.AgeCategory,
    cd.CommentVolumeCategory,
    cd.ScoreDifferenceFromPrevious,
    CASE
        WHEN cd.TotalPostsOwned > 1000 AND cd.ClosedQuestions < 10 AND cd.AvgAnswersPerQuestion > 3 THEN 'Proactive High Volume'
        WHEN cd.TotalPostsOwned > 500 AND cd.PostScore > 50 AND cd.CommentScoreRank <= 100 THEN 'Engaged Influencer'
        WHEN cd.AnswerCount > 10 AND cd.CommentCount > 20 THEN 'Highly Discussed'
        ELSE 'Standard Contributor'
    END AS UserEngagementTier,
    tp.TagName AS MostPopularTag,
    tp.TagRank AS MostPopularTagRank
FROM CombinedData cd
LEFT JOIN (
    SELECT PostId, TagName, TagRank
    FROM (
        SELECT
            p.Id AS PostId,
            t.TagName,
            t.TagRank,
            ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY t.TagRank ASC) as rn
        FROM Posts p
        CROSS JOIN TagPopularity t
        WHERE p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%'
    ) ranked_tags
    WHERE rn = 1
) tp ON cd.PostId = tp.PostId
WHERE cd.rn <= 500 -- Limit to top 500 recent high-scoring questions
ORDER BY cd.PostScore DESC, cd.PostCreationDate DESC;