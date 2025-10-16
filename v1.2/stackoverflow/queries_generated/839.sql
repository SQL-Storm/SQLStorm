-- {"query": "839.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1459} 

WITH RecursiveUserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(b.Id) AS BadgeCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserTopBadges AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT b.Name || ' (' || 
            CASE b.Class 
                WHEN 1 THEN 'Gold' 
                WHEN 2 THEN 'Silver' 
                WHEN 3 THEN 'Bronze' 
                ELSE 'Unknown' END || ')', ', ') AS BadgesList
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
),
PostsWithRelated AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Tags,
        pl.LinkTypeId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        pt.Name AS PostTypeName
    FROM 
        Posts p
    LEFT JOIN 
        PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN 
        LinkTypes lt ON lt.Id = pl.LinkTypeId
    LEFT JOIN
        PostTypes pt ON pt.Id = p.PostTypeId
),
QuestionsWithAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        u.DisplayName AS AnswerOwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM 
        Posts q
    LEFT JOIN 
        Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN
        Users u ON u.Id = a.OwnerUserId
    WHERE 
        q.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        QuestionId,
        COUNT(AnswerId) AS TotalAnswers,
        AVG(AnswerScore) AS AvgAnswerScore,
        MAX(AnswerScore) AS MaxAnswerScore,
        MIN(AnswerScore) AS MinAnswerScore
    FROM QuestionsWithAnswers
    GROUP BY QuestionId
),
HighActivityUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.BadgeCount,
        ua.AvgPostScore,
        ua.LastPostDate,
        utb.BadgesList
    FROM 
        RecursiveUserActivity ua
    LEFT JOIN 
        UserTopBadges utb ON utb.UserId = ua.UserId
    WHERE 
        ua.QuestionCount + ua.AnswerCount > 50
        AND ua.Reputation > 1000
        AND ua.BadgeCount > 10
),
QuestionsClosedRecently AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastClosedDate,
        cr.Name AS CloseReason
    FROM 
        PostHistory ph
    LEFT JOIN
        CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS INTEGER)
    WHERE 
        ph.PostHistoryTypeId = 10 -- Post Closed
        AND ph.CreationDate > NOW() - INTERVAL '90 days'
    GROUP BY ph.PostId, cr.Name
),
QuestionsWithCloseInfo AS (
    SELECT 
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        qc.LastClosedDate,
        qc.CloseReason
    FROM 
        Posts q
    LEFT JOIN 
        QuestionsClosedRecently qc ON qc.PostId = q.Id
    WHERE 
        q.PostTypeId = 1
)
SELECT 
    hau.UserId,
    hau.DisplayName,
    hau.Reputation,
    hau.QuestionCount,
    hau.AnswerCount,
    hau.BadgeCount,
    hau.AvgPostScore,
    hau.LastPostDate,
    COALESCE(hau.BadgesList, 'No Gold Badges') AS GoldBadges,
    q.Title AS SampleQuestionTitle,
    q.Score AS QuestionScore,
    q.ViewCount AS QuestionViewCount,
    q.LastClosedDate,
    q.CloseReason,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.MinAnswerScore,
    -- Window function to rank users by reputation and total posts
    RANK() OVER (ORDER BY hau.Reputation DESC, (hau.QuestionCount + hau.AnswerCount) DESC) AS UserRank,
    -- Expression with NULL logic and string manipulation
    CASE 
        WHEN q.CloseReason IS NOT NULL THEN 'Closed: ' || q.CloseReason 
        ELSE 'Open'
    END AS QuestionStatus,
    -- Correlated subquery to find the highest scoring answer for the sample question
    (SELECT a.Id 
     FROM Posts a 
     WHERE a.ParentId = q.Id AND a.PostTypeId = 2 
     ORDER BY a.Score DESC NULLS LAST LIMIT 1) AS TopAnswerId,
    -- Concatenate tags into a formatted string or show 'No Tags'
    COALESCE(
        (SELECT STRING_AGG(trim(tag), ', ') 
         FROM unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS tag),
        'No Tags'
    ) AS FormattedTags
FROM 
    HighActivityUsers hau
LEFT JOIN 
    Posts q ON q.OwnerUserId = hau.UserId AND q.PostTypeId = 1
LEFT JOIN 
    AnswerStats ans ON ans.QuestionId = q.Id
WHERE 
    q.CreationDate > hau.CreationDate + INTERVAL '30 days' -- questions after user creation + 30 days
    AND (ans.TotalAnswers IS NULL OR ans.TotalAnswers > 0)
ORDER BY
    hau.Reputation DESC,
    ans.AvgAnswerScore DESC NULLS LAST
LIMIT 100;
