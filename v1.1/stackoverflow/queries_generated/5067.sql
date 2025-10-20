-- {"query": "5067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1297} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END),0) AS TotalPostScore,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        SUM(v2.CountUpvotes) AS TotalUpvotesGiven,
        SUM(v2.CountDownvotes) AS TotalDownvotesGiven
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            v.UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS CountUpvotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS CountDownvotes
        FROM Votes v
        WHERE v.UserId IS NOT NULL
        GROUP BY v.UserId
    ) v2 ON v2.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
RecentQuestionsAndAnswers AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.OwnerUserId IS NOT NULL
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        nt.NumRecentQuestions,
        RANK() OVER (ORDER BY nt.NumRecentQuestions DESC, t.Count DESC) AS tag_rank
    FROM Tags t
    LEFT JOIN (
        SELECT
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
            COUNT(*) AS NumRecentQuestions
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.CreationDate > now() - interval '90 days' AND p.Tags IS NOT NULL
        GROUP BY tag
    ) nt ON nt.tag = t.TagName
),
VoteAggs AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(*) AS VoteCount
    FROM Votes v
    GROUP BY v.PostId
),
ClosedStats AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS TimesClosed,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS FirstClosedDate,
        array_agg(DISTINCT crt.Name) FILTER (WHERE ph.PostHistoryTypeId = 10 AND crt.Name IS NOT NULL) AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON
        ph.PostHistoryTypeId = 10
        AND (ph.Comment::int = crt.Id OR ph.Comment = crt.Name)
    GROUP BY ph.PostId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.CreationDate,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgesEarned,
    ua.TotalUpvotesGiven,
    ua.TotalDownvotesGiven,
    TQ.PostId AS MostRecentQuestionId,
    TQ.Title AS MostRecentQuestionTitle,
    TQ.Score AS MostRecentQuestionScore,
    ta.tag_rank AS TopTagRank,
    ta.TagName AS TopRecentTag,
    ta.NumRecentQuestions AS TopTagRecentUsage,
    COALESCE(vtM.Upvotes,0) AS RecentQuestionUpvotes,
    COALESCE(vtM.Downvotes,0) AS RecentQuestionDownvotes,
    cs.TimesClosed,
    cs.CloseReasons[1] AS FirstCloseReason,
    CASE
        WHEN ua.AnswerCount > 0 THEN ROUND(CAST(ua.TotalPostScore AS numeric)/NULLIF(ua.AnswerCount,0),2)
        ELSE NULL
    END AS AvgAnswerScore,
    CASE
        WHEN ua.QuestionCount > 0 THEN ROUND(CAST((ua.TotalUpvotesGiven - ua.TotalDownvotesGiven) AS numeric)/NULLIF(ua.QuestionCount,0), 2)
        ELSE NULL
    END AS VoteRatioPerQuestion,
    CASE
        WHEN regexp_match(TQ.Tags, '<(postgresql|sql|mysql)>') IS NOT NULL THEN TRUE ELSE FALSE END AS FocusedOnDBTags,
    CASE
        WHEN TQ.CreationDate IS NOT NULL AND TQ.CreationDate > now() - interval '7 days'
        THEN 'Active Last 7d'
        ELSE 'Inactive'
    END AS RecentActivity
FROM UserActivity ua
LEFT JOIN RecentQuestionsAndAnswers TQ
    ON TQ.OwnerUserId = ua.UserId AND TQ.PostTypeId = 1 AND TQ.rn = 1
LEFT JOIN LATERAL (
    SELECT ta.TagName, ta.NumRecentQuestions, ta.tag_rank
    FROM TopTags ta
    WHERE ta.NumRecentQuestions IS NOT NULL
    ORDER BY ta.NumRecentQuestions DESC, ta.Count DESC
    LIMIT 1
) ta ON TRUE
LEFT JOIN VoteAggs vtM ON vtM.PostId = TQ.PostId
LEFT JOIN ClosedStats cs ON cs.PostId = TQ.PostId
ORDER BY
    ua.Reputation DESC,
    ua.QuestionCount DESC,
    ua.AnswerCount DESC
LIMIT 50;