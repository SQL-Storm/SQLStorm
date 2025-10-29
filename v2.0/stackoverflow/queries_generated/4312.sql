-- {"query": "4312.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1500} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND p.Id = c.PostId
    WHERE u.Id > 0 -- Exclude community user
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        SUM(p.Score) AS TotalScoreForTag,
        AVG(p.ViewCount) AS AvgViewCountForTag,
        (SELECT COUNT(*) FROM Tags WHERE TagName LIKE CONCAT(t.TagName, '%') AND TagName <> t.TagName) AS SubTagCount
    FROM Tags t
    JOIN Posts p ON ',' + p.Tags + ',' LIKE CONCAT('%,', t.TagName, '%')
    WHERE p.PostTypeId = 1 -- Only consider questions for tag analysis
    GROUP BY t.TagName
),
LaggedScores AS (
    SELECT
        p.Id,
        p.Score,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
),
RankedVotes AS (
    SELECT
        v.UserId,
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.UserId, v.VoteTypeId ORDER BY v.CreationDate) AS VoteSequence
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3) -- Upvotes and Downvotes
    AND v.CreationDate >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount AS PostFavoriteCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    upa.DisplayName AS OwnerDisplayName,
    upa.Reputation AS OwnerReputation,
    COALESCE(ls.PreviousScore, 0) AS PreviousPostScore,
    COALESCE(ls.NextScore, 0) AS NextPostScore,
    (ls.NextScore - ls.PreviousScore) AS ScoreDifference,
    ts.TagName AS TopTag,
    ts.PostsWithTag,
    ts.TotalScoreForTag,
    ts.SubTagCount,
    COUNT(rv.VoteTypeId) AS VoteCountOnPost,
    SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN rv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.UserId IS NOT NULL AND c.UserId <> -1 AND c.CreationDate > rp.PostCreationDate) AS CommentsAfterPost,
    CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Is Duplicate' ELSE 'Not Duplicate' END AS DuplicateStatus
FROM RankedPosts rp
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
LEFT JOIN LaggedScores ls ON rp.PostId = ls.Id
LEFT JOIN TagStats ts ON rp.PostId = (SELECT p.Id FROM Posts p JOIN Tags t ON ',' + p.Tags + ',' LIKE CONCAT('%,', t.TagName, '%') WHERE t.TagName = ts.TagName AND p.PostTypeId = 1 AND p.Id = rp.PostId) -- Crude join to get a tag
LEFT JOIN RankedVotes rv ON rp.PostId = rv.PostId
WHERE rp.rn <= 100 -- Limit to top 100 recent posts per type
GROUP BY
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.PostAnswerCount,
    rp.PostCommentCount,
    rp.PostFavoriteCount,
    PostStatus,
    OwnerDisplayName,
    OwnerReputation,
    ls.PreviousScore,
    ls.NextScore,
    ScoreDifference,
    TopTag,
    ts.PostsWithTag,
    ts.TotalScoreForTag,
    ts.SubTagCount
HAVING UpVoteCount > DownVoteCount
ORDER BY rp.PostCreationDate DESC, rp.PostScore DESC
LIMIT 1000;
