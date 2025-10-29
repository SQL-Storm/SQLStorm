-- {"query": "2464.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1595} 
WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(v.CountVotes) AS TotalVotesCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS UserRank
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN (
            SELECT
                PostId,
                COUNT(*) AS CountVotes
            FROM Votes
            WHERE VoteTypeId IN (2,3) -- UpMod or DownMod
            GROUP BY PostId
        ) v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopQuestions AS (
    SELECT
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId,
        u.DisplayName AS OwnerName,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerTotal,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END) AS PopularAnswerCount
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserBadgeDetails AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS int) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
PostDiscussionActivity AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT COALESCE(u.DisplayName, c.UserDisplayName), ', ' ORDER BY COALESCE(u.DisplayName, c.UserDisplayName)) AS CommentAuthors
    FROM Comments c
    LEFT JOIN Users u ON c.UserId = u.Id
    GROUP BY c.PostId
),
UserReputationTrend AS (
    SELECT
        p.OwnerUserId AS UserId,
        DATE_TRUNC('month', p.CreationDate) AS ActivityMonth,
        COUNT(*) AS PostsMade,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY DATE_TRUNC('month', p.CreationDate)) AS ActivityMonthRank
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, DATE_TRUNC('month', p.CreationDate)
),
ConsolidatedResults AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.BadgeCount,
        COALESCE(ab.Bronze, 0) AS BronzeBadges,
        COALESCE(ab.Silver, 0) AS SilverBadges,
        COALESCE(ab.Gold, 0) AS GoldBadges,
        ua.TotalVotesCount,
        tq.Id AS TopQuestionId,
        tq.Title AS TopQuestionTitle,
        tq.Score AS TopQuestionScore,
        tq.ViewCount AS TopQuestionViews,
        COALESCE(ans.AnswerTotal, 0) AS AnswersToTopQuestion,
        COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ans.PopularAnswerCount, 0) AS PopularAnswerCount,
        qcr.CloseReason,
        qcr.CloseDate,
        pda.CommentCount,
        pda.UniqueCommenters,
        pda.LastCommentDate,
        pda.CommentAuthors
    FROM RecursiveUserActivity ua
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN BadgeCount ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class = 2 THEN BadgeCount ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class = 3 THEN BadgeCount ELSE 0 END) AS Bronze
        FROM UserBadgeDetails
        GROUP BY UserId
    ) ab ON ua.UserId = ab.UserId
    LEFT JOIN TopQuestions tq ON tq.OwnerUserId = ua.UserId AND tq.QuestionRank = 1
    LEFT JOIN AnswerStats ans ON ans.QuestionId = tq.Id
    LEFT JOIN QuestionCloseReasons qcr ON qcr.PostId = tq.Id
    LEFT JOIN PostDiscussionActivity pda ON pda.PostId = tq.Id
    WHERE ua.UserRank <= 100
)
SELECT
    cr.*,
    COALESCE(ur.PostsMade, 0) AS MonthlyPosts,
    COALESCE(ur.TotalScore, 0) AS MonthlyScore,
    COALESCE(ur.ActivityMonth, '1970-01-01'::timestamp) AS ActivityMonth,
    -- Complex string manipulation example: extract first tag, count tag length, explode tags into rows and re-aggregate
    split_part(cr.TopQuestionTags, '><', 1) AS FirstTag,
    LENGTH(cr.TopQuestionTags) AS TagStringLength,
    ARRAY_TO_STRING(ARRAY(
        SELECT DISTINCT TRIM(tag)
        FROM UNNEST(string_to_array(replace(replace(cr.TopQuestionTags, '><', ','), '<', ''), ',')) AS tag
        WHERE tag <> ''
        ORDER BY tag
    ), ',') AS DistinctTagList,
    -- Add a complex CASE expression involving NULL logic and correlated subquery
    CASE
        WHEN cr.CloseReason IS NOT NULL THEN
            'Closed due to: ' || cr.CloseReason || ' on ' || TO_CHAR(cr.CloseDate, 'YYYY-MM-DD')
        WHEN cr.AnswersToTopQuestion = 0 THEN
            'No answers yet'
        ELSE
            (
                SELECT
                    'Best answer score: ' || COALESCE(MAX(score), 0)
                FROM Posts ans
                WHERE ans.ParentId = cr.TopQuestionId AND ans.PostTypeId = 2
            )
    END AS StatusSummary
FROM (
    SELECT
        cr.*,
        COALESCE(tq.Tags, '') AS TopQuestionTags
    FROM ConsolidatedResults cr
    LEFT JOIN Posts tq ON tq.Id = cr.TopQuestionId
) cr
LEFT JOIN UserReputationTrend ur ON ur.UserId = cr.UserId AND ur.ActivityMonthRank = 1
ORDER BY cr.Reputation DESC, cr.UserId ASC
LIMIT 50;