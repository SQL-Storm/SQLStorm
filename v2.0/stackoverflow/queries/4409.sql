-- {"query": "4409.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1635}
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RepRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) DESC) AS AnswerScoreRankByYear
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        CreationDate,
        Score,
        AnswerCount,
        FavoriteCount,
        ROW_NUMBER() OVER (ORDER BY Score DESC, AnswerCount DESC) AS TopQuestionRank
    FROM Posts
    WHERE PostTypeId = 1 AND Score > 100 AND AnswerCount IS NOT NULL AND FavoriteCount IS NOT NULL
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.LastActivityDate) AS LastActivityOnPost,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        AVG(CASE WHEN p.OwnerUserId IS NOT NULL THEN CAST(p.Score AS DOUBLE PRECISION) ELSE NULL END) OVER (PARTITION BY p.OwnerUserId) AS AvgUserPostScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.ClosedDate, p.CommunityOwnedDate, p.Score, p.LastActivityDate
),
UserContributionSummary AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.UserCreationDate,
        rua.PostCount,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.CommentCount,
        pe.PostId,
        pe.Title AS PostTitle,
        pe.PostCreationDate,
        pe.UpVoteCount,
        pe.DownVoteCount,
        pe.CommentCount AS PostCommentCount,
        pe.PostStatus,
        pe.AvgUserPostScore,
        CASE
            WHEN LAG(pe.PostCreationDate, 1, pe.PostCreationDate) OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate) = pe.PostCreationDate THEN 'Same Day Post'
            WHEN EXTRACT(EPOCH FROM (pe.PostCreationDate - LAG(pe.PostCreationDate, 1, pe.PostCreationDate) OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate)))/3600 < 24 THEN 'Within 24 Hours'
            ELSE 'Longer Interval'
        END AS PostCadence,
        ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate DESC) AS UserPostSequence,
        pe.OwnerUserId
    FROM RankedUserActivity rua
    INNER JOIN PostEngagement pe ON rua.UserId = pe.OwnerUserId
    WHERE rua.RepRank <= 50
    GROUP BY rua.UserId, rua.DisplayName, rua.Reputation, rua.UserCreationDate, rua.PostCount, rua.QuestionCount, rua.AnswerCount, rua.CommentCount, pe.PostId, pe.Title, pe.PostCreationDate, pe.UpVoteCount, pe.DownVoteCount, pe.CommentCount, pe.PostStatus, pe.AvgUserPostScore, pe.OwnerUserId
)
SELECT
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserCreationDate,
    ucs.PostCount,
    ucs.QuestionCount,
    ucs.AnswerCount,
    ucs.CommentCount,
    ucs.PostId,
    ucs.PostTitle,
    ucs.PostCreationDate,
    ucs.UpVoteCount,
    ucs.DownVoteCount,
    ucs.PostCommentCount,
    ucs.PostStatus,
    ucs.AvgUserPostScore,
    ucs.PostCadence,
    (SELECT Name FROM PostTypes WHERE Id = (SELECT PostTypeId FROM Posts WHERE Id = ucs.PostId)) AS ActualPostType,
    CASE
        WHEN ucs.UserPostSequence = 1 THEN 'Most Recent'
        WHEN ucs.UserPostSequence <= 5 THEN 'Top 5 Recent'
        ELSE 'Other'
    END AS UserPostRecency,
    COALESCE(t.TagName, 'N/A') AS PrimaryTag,
    COALESCE(CASE WHEN t.Id IS NULL THEN 'No Tag' ELSE 'Has Tag' END, 'Unknown') AS TagPresence,
    CASE
        WHEN LOWER(ucs.PostTitle) LIKE '%close%' OR LOWER(ucs.PostTitle) LIKE '%delete%' THEN 'Potentially Sensitive Title'
        WHEN LOWER(ucs.PostTitle) LIKE '%error%' THEN 'Error Mentioned'
        ELSE 'Standard Title'
    END AS TitleContentCategory,
    CASE
        WHEN ucs.PostStatus = 'Closed' AND ucs.DownVoteCount > ucs.UpVoteCount * 2 THEN 'Likely Unpopular Closed Post'
        WHEN ucs.PostStatus = 'Active' AND ucs.UpVoteCount > ucs.DownVoteCount * 3 AND ucs.PostCommentCount > 5 THEN 'Highly Engaged Active Post'
        ELSE 'Standard Post Activity'
    END AS PostActivityProfile,
    ucs.UserPostSequence
FROM UserContributionSummary ucs
LEFT JOIN Posts p_tag ON ucs.PostId = p_tag.Id
LEFT JOIN Tags t ON
    CASE
        WHEN p_tag.Tags IS NULL THEN NULL
        WHEN POSITION('>' IN p_tag.Tags) > 1 THEN SUBSTRING(p_tag.Tags FROM 2 FOR POSITION('>' IN p_tag.Tags) - 2)
        ELSE p_tag.Tags
    END = t.TagName
WHERE ucs.UserPostSequence <= 10
GROUP BY
    ucs.UserId,
    ucs.DisplayName,
    ucs.Reputation,
    ucs.UserCreationDate,
    ucs.PostCount,
    ucs.QuestionCount,
    ucs.AnswerCount,
    ucs.CommentCount,
    ucs.PostId,
    ucs.PostTitle,
    ucs.PostCreationDate,
    ucs.UpVoteCount,
    ucs.DownVoteCount,
    ucs.PostCommentCount,
    ucs.PostStatus,
    ucs.AvgUserPostScore,
    ucs.PostCadence,
    ucs.UserPostSequence,
    t.TagName,
    t.Id
ORDER BY ucs.UserId, ucs.PostCreationDate DESC
LIMIT 1000;