-- {"query": "1063.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2177} 

WITH RecursiveTagHierarchy AS (
    -- Recursive CTE to find tags related by name similarity (prefix matching)
    SELECT
        t.Id,
        t.TagName,
        1 AS Level
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName <> ''

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        rh.Level + 1
    FROM Tags t2
    INNER JOIN RecursiveTagHierarchy rh ON t2.TagName LIKE rh.TagName || '%'
    WHERE t2.Id <> rh.Id AND rh.Level < 3
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCreated,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCreated,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COALESCE(SUM(vb.VotesForUser),0) AS TotalVotesReceived,
        MAX(p.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN (
        -- Votes received on user's posts (excluding community-owned)
        SELECT p.OwnerUserId, COUNT(*) AS VotesForUser
        FROM Votes v
        INNER JOIN Posts p ON p.Id = v.PostId AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
        WHERE v.VoteTypeId IN (2,3) -- UpMod and DownMod
        GROUP BY p.OwnerUserId
    ) vb ON vb.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1 -- Gold badges only
    WHERE u.Reputation > 100 -- Filter interesting users
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        BOOL_OR(p.ClosedDate IS NOT NULL) AS IsClosed,
        -- Rank answers per question by score desc and creation date asc
        RANK() OVER (
            PARTITION BY COALESCE(p.ParentId, p.Id)
            ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC
        ) AS AnswerRank
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId, p.ParentId, p.Title, p.ClosedDate
),
DuplicatesAndLinks AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE p.PostTypeId = 1
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId AND pht.Name = 'Post Closed'
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS smallint)
    WHERE ph.PostId IS NOT NULL
    GROUP BY ph.PostId, crt.Name
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
AnswerAcceptanceStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        COUNT(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 END) AS AcceptedAnswerCount
    FROM Posts p
    INNER JOIN Posts q ON q.Id = p.ParentId AND q.PostTypeId = 1
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsCreated,
    ua.AnswersCreated,
    ua.CommentsMade,
    ua.TotalVotesReceived,
    ua.BadgeCount AS GoldBadgeCount,
    COALESCE(ubsSilver.BadgeCount,0) AS SilverBadgeCount,
    COALESCE(ubsBronze.BadgeCount,0) AS BronzeBadgeCount,
    pe.PostId,
    pe.PostTypeId,
    pe.Score,
    pe.ViewCount,
    pe.CommentCount,
    pe.UpVotes,
    pe.DownVotes,
    pe.IsClosed,
    pe.AnswerRank,
    dq.LinkTypeName,
    qcr.CloseReason,
    qcr.CloseVotesCount,
    ats.AnswerCount,
    ats.AcceptedAnswerCount,
    -- Complex calculated field with NULL-safe logic and string functions
    CASE
        WHEN pe.PostTypeId = 1 THEN
            'Q: ' || COALESCE(NULLIF(pe.Title, ''), '[No Title]')
                || ' [' || COALESCE(pe.Tags, '<untagged>') || '] '
                || ' Score:' || COALESCE(pe.Score,0) 
                || ' Views:' || COALESCE(pe.ViewCount,0)
                || ' Comments:' || COALESCE(pe.CommentCount,0)
        WHEN pe.PostTypeId = 2 THEN
            'A to Q#' || COALESCE(pe.ParentId::text, 'N/A') 
                || ' Score:' || COALESCE(pe.Score,0)
                || ' Accepted:' || CASE WHEN pe.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = pe.ParentId) THEN 'Yes' ELSE 'No' END
        ELSE 'Other PostType'
    END AS PostSummary,
    -- Window function to calculate user's rank by reputation among all users
    RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank
FROM UserActivity ua
LEFT JOIN PostEngagement pe ON pe.OwnerUserId = ua.UserId
LEFT JOIN DuplicatesAndLinks dq ON dq.QuestionId = pe.Id
LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = pe.Id
LEFT JOIN UserBadgeSummary ubsSilver ON ubsSilver.UserId = ua.UserId AND ubsSilver.Class = 2
LEFT JOIN UserBadgeSummary ubsBronze ON ubsBronze.UserId = ua.UserId AND ubsBronze.Class = 3
LEFT JOIN AnswerAcceptanceStats ats ON ats.QuestionId = pe.Id
WHERE ua.Reputation > 500
  AND (pe.PostTypeId IS NULL OR pe.IsClosed = FALSE)
ORDER BY ua.Reputation DESC, pe.Score DESC NULLS LAST
LIMIT 100
UNION
-- Include top 10 highest scored closed questions with duplicates for contrast
SELECT
    NULL AS UserId,
    '[Closed Question]' AS DisplayName,
    NULL::int AS Reputation,
    NULL::int AS QuestionsCreated,
    NULL::int AS AnswersCreated,
    NULL::int AS CommentsMade,
    NULL::int AS TotalVotesReceived,
    NULL::int AS GoldBadgeCount,
    NULL::int AS SilverBadgeCount,
    NULL::int AS BronzeBadgeCount,
    p.Id AS PostId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    TRUE AS IsClosed,
    NULL::int AS AnswerRank,
    NULL AS LinkTypeName,
    (SELECT crt.Name FROM PostHistory ph JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS smallint)
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10) LIMIT 1) AS CloseReason,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) AS CloseVotesCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS AnswerCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.Id = p.AcceptedAnswerId) AS AcceptedAnswerCount,
    'Closed Q: ' || COALESCE(NULLIF(p.Title, ''), '[No Title]')
        || ' Tags: ' || COALESCE(p.Tags, '<untagged>')
        || ' Score:' || COALESCE(p.Score,0)
        || ' Views:' || COALESCE(p.ViewCount,0)
        || ' Comments:' || (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)
        || ' Closed for: ' || COALESCE(
            (SELECT crt.Name FROM PostHistory ph JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS smallint)
             WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 LIMIT 1), 'Unknown')
    AS PostSummary,
    NULL::int AS ReputationRank
FROM Posts p
WHERE p.PostTypeId = 1
  AND p.ClosedDate IS NOT NULL
  AND p.Score > 10
ORDER BY p.Score DESC
LIMIT 10;
