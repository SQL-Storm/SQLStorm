-- {"query": "4687.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1655}
WITH RankedUserPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate ELSE NULL END) AS LatestQuestionDate,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate ELSE NULL END) AS LatestAnswerDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AverageCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL AND c.UserId > 0
    GROUP BY c.UserId
),
UserVoteActivity AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountyStartCount,
        MAX(v.CreationDate) AS LatestVoteDate
    FROM Votes v
    WHERE v.UserId IS NOT NULL AND v.UserId > 0
    GROUP BY v.UserId
),
LatestUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(up.QuestionCount, 0) AS TotalQuestions,
        COALESCE(up.AnswerCount, 0) AS TotalAnswers,
        COALESCE(up.TotalQuestionScore, 0) AS TotalQuestionScore,
        COALESCE(up.TotalAnswerScore, 0) AS TotalAnswerScore,
        up.LatestQuestionDate,
        up.LatestAnswerDate,
        COALESCE(ca.CommentCount, 0) AS TotalComments,
        COALESCE(ca.AverageCommentScore, 0) AS AverageCommentScore,
        ca.LatestCommentDate,
        COALESCE(va.UpVoteCount, 0) AS TotalUpVotes,
        COALESCE(va.DownVoteCount, 0) AS TotalDownVotes,
        COALESCE(va.BountyStartCount, 0) AS TotalBountyStarts,
        va.LatestVoteDate,
        CASE
            WHEN rp.rn = 1 THEN 'Most Recent'
            ELSE 'Other'
        END AS RecencyFlag
    FROM Users u
    LEFT JOIN UserPostStats up ON u.Id = up.OwnerUserId
    LEFT JOIN UserCommentActivity ca ON u.Id = ca.UserId
    LEFT JOIN UserVoteActivity va ON u.Id = va.UserId
    LEFT JOIN RankedUserPosts rp ON u.Id = rp.OwnerUserId AND rp.rn = 1
    WHERE u.Id IS NOT NULL AND u.Id > 0
)
SELECT
    l.UserId,
    l.DisplayName,
    l.Reputation,
    l.UserCreationDate,
    l.LastAccessDate,
    l.TotalQuestions,
    l.TotalAnswers,
    l.TotalQuestionScore,
    l.TotalAnswerScore,
    l.LatestQuestionDate,
    l.LatestAnswerDate,
    l.TotalComments,
    l.AverageCommentScore,
    l.LatestCommentDate,
    l.TotalUpVotes,
    l.TotalDownVotes,
    l.TotalBountyStarts,
    l.LatestVoteDate,
    l.RecencyFlag,
    CASE
        WHEN l.TotalQuestions > 1000 THEN 'Prolific Questioner'
        WHEN l.TotalAnswers > 5000 THEN 'Prolific Answerer'
        WHEN l.TotalComments > 10000 THEN 'Active Commenter'
        WHEN l.TotalUpVotes > 20000 THEN 'Highly Voted User'
        ELSE 'Standard User'
    END AS UserCategory,
    CAST(l.Reputation AS NUMERIC) / (l.TotalQuestions + 1) AS ReputationPerQuestion,
    CASE
        WHEN l.LatestQuestionDate IS NOT NULL AND l.LatestAnswerDate IS NOT NULL THEN
            CASE
                WHEN l.LatestQuestionDate > l.LatestAnswerDate THEN 'Asked More Recently Than Answered'
                WHEN l.LatestAnswerDate > l.LatestQuestionDate THEN 'Answered More Recently Than Asked'
                ELSE 'Last Question/Answer Same Time'
            END
        WHEN l.LatestQuestionDate IS NOT NULL THEN 'Only Asked Questions'
        WHEN l.LatestAnswerDate IS NOT NULL THEN 'Only Answered'
        ELSE 'No Questions or Answers'
    END AS PostingActivityTrend,
    COALESCE(LENGTH(u.AboutMe), 0) AS AboutMeLength,
    CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    CASE WHEN u.Location LIKE '%USA%' THEN 'Located in USA' WHEN u.Location LIKE '%UK%' THEN 'Located in UK' WHEN u.Location IS NULL THEN 'No Location Provided' ELSE 'Other Location' END AS LocationInsight
FROM LatestUserActivity l
JOIN Users u ON l.UserId = u.Id
WHERE l.UserCreationDate < DATE '2023-01-01'
UNION ALL
SELECT
    l.UserId,
    l.DisplayName,
    l.Reputation,
    l.UserCreationDate,
    l.LastAccessDate,
    l.TotalQuestions,
    l.TotalAnswers,
    l.TotalQuestionScore,
    l.TotalAnswerScore,
    l.LatestQuestionDate,
    l.LatestAnswerDate,
    l.TotalComments,
    l.AverageCommentScore,
    l.LatestCommentDate,
    l.TotalUpVotes,
    l.TotalDownVotes,
    l.TotalBountyStarts,
    l.LatestVoteDate,
    l.RecencyFlag,
    'New User Category' AS UserCategory,
    CAST(l.Reputation AS NUMERIC) / (l.TotalQuestions + 1) AS ReputationPerQuestion,
    CASE
        WHEN l.LatestQuestionDate IS NOT NULL AND l.LatestAnswerDate IS NOT NULL THEN
            CASE
                WHEN l.LatestQuestionDate > l.LatestAnswerDate THEN 'Asked More Recently Than Answered'
                WHEN l.LatestAnswerDate > l.LatestQuestionDate THEN 'Answered More Recently Than Asked'
                ELSE 'Last Question/Answer Same Time'
            END
        WHEN l.LatestQuestionDate IS NOT NULL THEN 'Only Asked Questions'
        WHEN l.LatestAnswerDate IS NOT NULL THEN 'Only Answered'
        ELSE 'No Questions or Answers'
    END AS PostingActivityTrend,
    COALESCE(LENGTH(u.AboutMe), 0) AS AboutMeLength,
    CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    CASE WHEN u.Location LIKE '%USA%' THEN 'Located in USA' WHEN u.Location LIKE '%UK%' THEN 'Located in UK' WHEN u.Location IS NULL THEN 'No Location Provided' ELSE 'Other Location' END AS LocationInsight
FROM LatestUserActivity l
JOIN Users u ON l.UserId = u.Id
WHERE l.UserCreationDate >= DATE '2023-01-01'
ORDER BY Reputation DESC, UserCreationDate ASC;