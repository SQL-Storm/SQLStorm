-- {"query": "4573.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1382} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        AVG(CASE WHEN p.Score > 0 THEN p.Score ELSE NULL END) AS AvgPositiveScore,
        COUNT(CASE WHEN c.Id IS NOT NULL THEN c.Id ELSE NULL END) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 -- Exclude community user and system accounts
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF(day, p.ClosedDate, p.LastActivityDate) ELSE NULL END AS DaysSinceClosed,
        p.Tags,
        ua.Reputation AS OwnerReputation,
        ua.UserCreationDate AS OwnerCreationDate,
        COALESCE(ua.TotalPostsCreated, 0) AS OwnerTotalPosts,
        ua.QuestionsAsked AS OwnerQuestionsAsked,
        ua.AnswersGiven AS OwnerAnswersGiven,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate links
        ) AS DuplicateLinkCount,
        (
            SELECT TOP 1 ph.UserDisplayName
            FROM PostHistory ph
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
            ORDER BY ph.CreationDate DESC
        ) AS CloserDisplayName
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
RankedComments AS (
    SELECT
        c.PostId,
        c.UserId,
        c.Score AS CommentScore,
        c.CreationDate AS CommentCreationDate,
        ROW_NUMBER() OVER(PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate ASC) as rn
    FROM Comments c
)
SELECT
    pd.PostId,
    pd.Title,
    pd.PostTypeName,
    pd.PostCreationDate,
    pd.PostScore,
    pd.ViewCount,
    pd.OwnerDisplayName,
    pd.OwnerReputation,
    pd.OwnerCreationDate,
    pd.OwnerTotalPosts,
    pd.OwnerQuestionsAsked,
    pd.OwnerAnswersGiven,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.ClosedDate,
    pd.DaysSinceClosed,
    pd.Tags,
    pd.DuplicateLinkCount,
    pd.CloserDisplayName,
    rc_top.CommentScore AS TopCommentScore,
    rc_top.CommentCreationDate AS TopCommentDate,
    rpe.UserId AS LastEditorUserId,
    rpe.CreationDate AS LastEditDate,
    rpe.PostHistoryTypeId AS LastEditType,
    CASE
        WHEN pd.OwnerReputation >= 10000 AND pd.PostScore > 50 THEN 'High Value User, High Score Post'
        WHEN pd.OwnerReputation < 1000 THEN 'Low Reputation User'
        WHEN pd.DaysSinceClosed IS NOT NULL AND pd.DaysSinceClosed < 7 THEN 'Recently Closed'
        WHEN pd.Tags LIKE '%<performance>%' THEN 'Performance Tagged'
        ELSE 'Other'
    END AS PostCategory,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = pd.PostId AND v.VoteTypeId = 2 -- UpVotes
    ) AS TotalUpVotes,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = pd.PostId AND v.VoteTypeId = 3 -- DownVotes
    ) AS TotalDownVotes,
    STRFTIME('%Y-%m', pd.PostCreationDate) AS PostMonthYear,
    UPPER(LEFT(pd.OwnerDisplayName, 3)) AS OwnerDisplayNamePrefix
FROM PostDetails pd
LEFT JOIN RankedPostEdits rpe ON pd.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN RankedComments rc_top ON pd.PostId = rc_top.PostId AND rc_top.rn = 1
WHERE pd.PostScore > -5 -- Exclude severely downvoted posts for better analysis focus
ORDER BY pd.PostScore DESC, pd.PostCreationDate DESC, pd.OwnerReputation DESC;
