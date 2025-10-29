-- {"query": "2576.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1472} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.WikiPostId,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        child.WikiPostId,
        rh.Level + 1
    FROM Tags child
    JOIN PostLinks pl ON pl.PostId = child.WikiPostId
    JOIN RecursiveTagHierarchy rh ON rh.WikiPostId = pl.RelatedPostId
    WHERE child.IsRequired = 1 AND rh.Level < 3
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COALESCE(SUM(vtCount.UpVotes),0) AS TotalUpVotes,
        COALESCE(SUM(vtCount.DownVotes),0) AS TotalDownVotes,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        MAX(b.Date) AS LastBadgeAwarded,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC, u.Reputation DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT 
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        WHERE v.PostId = p.Id
    ) vtCount ON TRUE
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
QuestionAnswerDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.OwnerDisplayName,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        u.DisplayName AS AnswerOwnerDisplayName,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM TopQuestions q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.QuestionRank <= 5
),
CloseReasonsSummary AS (
    SELECT
        cht.Id AS CloseReasonId,
        cht.Name AS CloseReasonName,
        COUNT(DISTINCT ph.PostId) AS ClosedPostsCount
    FROM PostHistory ph
    JOIN PostHistoryTypes chtId ON ph.PostHistoryTypeId = chtId.Id
    JOIN CloseReasonTypes cht ON cht.Id = CAST(ph.Comment AS INT) -- CloseReasonId stored in Comment when PostHistoryTypeId=10
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY cht.Id, cht.Name
),
PostEngagementWindow AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentsCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotes,
        AVG(p.Score) OVER () AS AvgScoreAllPosts,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankWithinType
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
),
StringAggregatedTags AS (
    SELECT
        p.Id AS PostId,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS TagsArrayString
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName
    ) AS tagNames ON TRUE
    LEFT JOIN Tags t ON t.TagName = tagNames.TagName
    GROUP BY p.Id
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.BadgesCount,
    ua.LastBadgeAwarded,
    qad.QuestionId,
    qad.Title AS QuestionTitle,
    qad.AnswerId,
    qad.AnswerOwnerDisplayName,
    qad.AnswerScore,
    qad.IsAccepted,
    cr.CloseReasonName,
    pew.CommentsCount,
    pew.UpVotes,
    pew.DownVotes,
    pew.AvgScoreAllPosts,
    pew.ScoreRankWithinType,
    sat.TagsArrayString,
    rh.Level AS TagHierarchyLevel,
    rh.TagName AS RecursiveTagName
FROM UserActivity ua
LEFT JOIN QuestionAnswerDetails qad ON qad.OwnerUserId = ua.UserId AND qad.AnswerRank = 1
LEFT JOIN CloseReasonsSummary cr ON cr.CloseReasonId = (
    SELECT CAST(ph.Comment AS INT)
    FROM PostHistory ph
    WHERE ph.PostId = qad.QuestionId AND ph.PostHistoryTypeId = 10
    LIMIT 1
)
LEFT JOIN PostEngagementWindow pew ON pew.PostId = IFNULL(qad.AnswerId, qad.QuestionId)
LEFT JOIN StringAggregatedTags sat ON sat.PostId = qad.QuestionId
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(TRIM(BOTH '<>' FROM qad.Tags), '><'))
WHERE ua.ActivityRank <= 10
ORDER BY ua.ActivityRank, qad.QuestionScore DESC, qad.AnswerScore DESC;
