-- {"query": "1393.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1378} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
        COALESCE(SUM(v.VoteCount), 0) AS VotesReceived,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        MAX(b.Class) AS HighestBadgeClass,
        COUNT(DISTINCT posAccepted.Id) AS AcceptedAnswersCount,
        MAX(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS MaxPostScore,
        MIN(p.CreationDate) AS FirstPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY COUNT(p.Id) DESC NULLS LAST) AS ActivityRankPerLocation
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON v.PostId = p.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Posts posAccepted ON posAccepted.Id = p.AcceptedAnswerId AND posAccepted.OwnerUserId = u.Id
    WHERE
        u.Reputation > 0
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        p.AnswerCount,
        STRING_AGG(c.Text, ' | ' ORDER BY c.CreationDate DESC) AS LatestCommentsText,
        COUNT(c.Id) AS CommentCount,
        EXISTS (
            SELECT 1
            FROM PostHistory ph
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 -- Closed
        ) AS IsClosed,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS Status
    FROM
        Posts p
        LEFT JOIN Users u ON u.Id = p.OwnerUserId
        LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE
        p.PostTypeId = 1
        AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
        AND p.ViewCount > 1000
    GROUP BY
        p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, p.AnswerCount, p.ClosedDate
),
DuplicatedQuestions AS (
    SELECT DISTINCT
        postlink.PostId AS DuplicateId,
        related.PostId AS OriginalId,
        original.Title AS OriginalTitle,
        duplicate.Title AS DuplicateTitle,
        postlink.CreationDate AS LinkDate
    FROM
        PostLinks postlink
        JOIN Posts related ON related.Id = postlink.RelatedPostId AND related.PostTypeId = 1 -- Original question
        JOIN Posts original ON original.Id = related.Id AND original.PostTypeId = 1
        JOIN Posts duplicate ON duplicate.Id = postlink.PostId AND duplicate.PostTypeId = 1 -- Duplicate question
    WHERE
        postlink.LinkTypeId = 3 -- Duplicate
),
VotesWindow AS (
    SELECT
        p.Id AS PostId,
        v.VoteTypeId,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId, v.VoteTypeId ORDER BY v.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, v.VoteTypeId ORDER BY v.CreationDate DESC) AS RecentVoteRank
    FROM
        Votes v
        JOIN Posts p ON p.Id = v.PostId
    WHERE
        p.OwnerUserId IS NOT NULL
),
TopUsersByAcceptedAnswers AS (
    SELECT
        ua.UserId, 
        ua.DisplayName, 
        ua.AcceptedAnswersCount,
        ua.Reputation,
        ua.ActivityRankPerLocation,
        ua.BadgesCount,
        ua.HighestBadgeClass,
        ua.TotalPosts
    FROM
        UserActivity ua
    WHERE 
        ua.AcceptedAnswersCount > 10
    ORDER BY
        ua.AcceptedAnswersCount DESC
    LIMIT 10
)
SELECT 
    tq.Id AS QuestionId,
    tq.Title,
    tq.Tags,
    STRING_AGG(dt.DuplicateTitle, ', ') AS DuplicateQuestions,
    tq.ViewCount,
    tq.Score AS QuestionScore,
    ua.DisplayName AS QuestionOwner,
    ua.Reputation AS OwnerReputation,
    tue.DisplayName AS TopUser,
    tue.AcceptedAnswersCount AS TopUserAcceptedAnswers,
    tue.BadgesCount AS TopUserBadgesCount,
    vu.RunningVoteCount AS UserVoteCount,
    COALESCE(NULLIF(tq.LatestCommentsText, ''), 'No Comments') AS CommentsSummary,
    CASE 
        WHEN tq.Status = 'Closed' THEN 'Closed'
        ELSE 'Open'
    END AS QuestionStatus,
    ROW_NUMBER() OVER (PARTITION BY ua.Location ORDER BY tq.Score DESC) AS ScoreRankWithinLocation
FROM
    TopQuestions tq
    LEFT JOIN UserActivity ua ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = tq.Id)
    LEFT JOIN DuplicatedQuestions dt ON dt.OriginalId = tq.Id
    LEFT JOIN TopUsersByAcceptedAnswers tue ON tue.UserId = ua.UserId
    LEFT JOIN VotesWindow vu ON vu.PostId = tq.Id AND vu.VoteTypeId = 2 AND vu.RecentVoteRank = 1 -- Most recent UpMod vote???
WHERE
    ua.Location IS NOT NULL
GROUP BY
    tq.Id, tq.Title, tq.Tags, tq.ViewCount, tq.Score, ua.DisplayName, ua.Reputation, tue.DisplayName,
    tue.AcceptedAnswersCount, tue.BadgesCount, vu.RunningVoteCount, tq.LatestCommentsText, tq.Status, ua.Location
ORDER BY
    tq.Score DESC,
    ua.Reputation DESC,
    tue.AcceptedAnswersCount DESC
LIMIT 50
UNION
SELECT 
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
ORDER BY 12 NULLS LAST;
