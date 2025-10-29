WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        LAG(p.Score) OVER (ORDER BY p.Score DESC) - p.Score AS ScoreDifferenceFromPrevious
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.Score) AS MaxScore,
        MAX(p.ViewCount) AS MaxViews,
        MAX(p.CreationDate) AS LastActivity,
        STRING_AGG(CASE WHEN p.PostTypeId = 2 THEN p.Title END, '; ') AS RecentAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count AS CountDifference,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS RankByCount
    FROM Tags t
    WHERE t.Count > 100
),
PostDetails AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Low Voted'
            ELSE 'No Votes'
        END AS VotingLevel,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN
                (SELECT COUNT(*) FROM (
                    SELECT regexp_split_to_table(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') AS tag
                ) AS _t)
            ELSE 0
        END AS TagCount,
        EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) AS DaysSinceCreation,
        CASE 
            WHEN p.CreationDate < DATE '2010-01-01' THEN 'Legacy'
            WHEN p.CreationDate < DATE '2015-01-01' THEN 'Early'
            WHEN p.CreationDate < DATE '2020-01-01' THEN 'Recent'
            ELSE 'Modern'
        END AS Era,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        COALESCE((
            SELECT COUNT(*) 
            FROM Comments c 
            WHERE c.PostId = p.Id AND c.Score > 0
        ), 0) AS PositiveCommentCount,
        COALESCE((
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.PostId = p.Id AND v.VoteTypeId = 2
        ), 0) AS UpVoteCount,
        COALESCE((
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.PostId = p.Id AND v.VoteTypeId = 3
        ), 0) AS DownVoteCount,
        CASE 
            WHEN p.OwnerUserId IS NOT NULL THEN (
                SELECT u.DisplayName 
                FROM Users u 
                WHERE u.Id = p.OwnerUserId
                LIMIT 1
            )
            ELSE 'Community Wiki'
        END AS OwnerName,
        COALESCE((
            SELECT STRING_AGG(t2.TagName, ', ')
            FROM (
                SELECT regexp_split_to_table(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') AS tag
            ) AS t1
            JOIN Tags t2 ON t2.TagName = t1.tag
        ), '') AS TagList
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
FilteredPosts AS (
    SELECT 
        PostDetails.Id,
        PostDetails.Title,
        PostDetails.Body,
        PostDetails.Score,
        PostDetails.ViewCount,
        PostDetails.OwnerUserId,
        PostDetails.CreationDate,
        PostDetails.LastActivityDate,
        PostDetails.Tags,
        PostDetails.AcceptedAnswerId,
        PostDetails.AnswerCount,
        PostDetails.CommentCount,
        PostDetails.FavoriteCount,
        PostDetails.PostType,
        PostDetails.VotingLevel,
        PostDetails.TagCount,
        PostDetails.DaysSinceCreation,
        PostDetails.Era,
        PostDetails.HasAcceptedAnswer,
        PostDetails.PositiveCommentCount,
        PostDetails.UpVoteCount,
        PostDetails.DownVoteCount,
        PostDetails.OwnerName,
        PostDetails.TagList
    FROM PostDetails
    WHERE Score > 0 
        AND ViewCount > 10
        AND DaysSinceCreation < 365
        AND (TagCount >= 1 OR PostType = 'Question')
),
AnswerWithQuestion AS (
    SELECT 
        a.Id AS AnswerId,
        a.PostTypeId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwner,
        a.CreationDate AS AnswerDate,
        COALESCE(a.ParentId, 0) AS QuestionId,
        q.Title AS QuestionTitle,
        q.Score AS QuestionScore,
        q.OwnerUserId AS QuestionOwner,
        q.CreationDate AS QuestionDate,
        CASE 
            WHEN a.Score > q.Score THEN 'Better Answer'
            WHEN a.Score = q.Score THEN 'Equal Answer'
            ELSE 'Worse Answer'
        END AS AnswerQuality
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 AND q.PostTypeId = 1
)
SELECT 
    rp.Id AS PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.UserPostRank,
    rp.GlobalScoreRank,
    rp.ScoreDifferenceFromPrevious,
    us.DisplayName AS OwnerDisplayName,
    us.Reputation AS OwnerReputation,
    us.TotalPosts AS OwnerTotalPosts,
    us.Questions AS OwnerQuestions,
    us.Answers AS OwnerAnswers,
    us.TotalScore AS OwnerTotalScore,
    us.AvgScore AS OwnerAvgScore,
    us.MaxScore AS OwnerMaxScore,
    us.MaxViews AS OwnerMaxViews,
    us.LastActivity AS OwnerLastActivity,
    ta.TagName,
    ta.TagCount AS TagFrequency,
    ta.CountDifference AS TagCountChange,
    ta.RankByCount,
    fp.PostType,
    fp.VotingLevel,
    fp.TagCount AS PostTagCount,
    fp.DaysSinceCreation,
    fp.Era,
    fp.HasAcceptedAnswer,
    fp.PositiveCommentCount,
    fp.UpVoteCount,
    fp.DownVoteCount,
    fp.OwnerName,
    fp.TagList,
    awq.AnswerId,
    awq.AnswerScore,
    awq.AnswerOwner,
    awq.QuestionId,
    awq.QuestionTitle,
    awq.QuestionScore,
    awq.AnswerQuality
FROM RankedPosts rp
LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
LEFT JOIN TagAnalysis ta ON rp.Tags LIKE '%' || ta.TagName || '%'
LEFT JOIN FilteredPosts fp ON rp.Id = fp.Id
LEFT JOIN AnswerWithQuestion awq ON rp.Id = awq.AnswerId
WHERE 
    (fp.TagCount >= 2 OR fp.PostType = 'Question')
    AND us.Reputation > 1000
    AND (awq.AnswerQuality = 'Better Answer' OR awq.AnswerQuality IS NULL)
    AND ta.TagCount >= 200
    AND (us.MaxScore > 50 OR us.TotalScore > 100)
    AND (rp.ScoreDifferenceFromPrevious > 50 OR rp.ScoreDifferenceFromPrevious IS NULL)
ORDER BY rp.GlobalScoreRank ASC, rp.Score DESC
LIMIT 500;