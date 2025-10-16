-- {"query": "1112.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2137} 

WITH RecursivePostParents AS (
    SELECT 
        Id, ParentId, PostTypeId, OwnerUserId, CreationDate, Score,
        ARRAY[Id] AS AncestorPath,
        1 AS Depth
    FROM Posts
    WHERE ParentId IS NULL AND PostTypeId = 1

    UNION ALL

    SELECT 
        p.Id, p.ParentId, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score,
        r.AncestorPath || p.Id,
        r.Depth + 1
    FROM Posts p
    INNER JOIN RecursivePostParents r ON p.ParentId = r.Id
    WHERE p.PostTypeId = 2
),

UserBadgeAggregates AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),

TopUsers AS (
    SELECT 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        COALESCE(uba.GoldBadges,0) AS GoldBadges,
        COALESCE(uba.SilverBadges,0) AS SilverBadges,
        COALESCE(uba.BronzeBadges,0) AS BronzeBadges,
        u.Views, u.UpVotes, u.DownVotes,
        uba.LastBadgeDate,
        RANK() OVER (ORDER BY u.Reputation DESC, uba.GoldBadges DESC) AS RepRank
    FROM Users u
    LEFT JOIN UserBadgeAggregates uba ON u.Id = uba.UserId
    WHERE u.Reputation > 10000
),

PostAndCommentsData AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.AcceptedAnswerId,
        COALESCE(c.CommentCount,0) AS CommentCount,
        COALESCE(v.UpVotes,0) AS UpVotes,
        COALESCE(v.DownVotes,0) AS DownVotes,
        p.LastActivityDate
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON p.Id = c.PostId
    LEFT JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        JOIN VoteTypes vt ON Votes.VoteTypeId = vt.Id
        GROUP BY PostId
    ) v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers only
),

AcceptedAnswerDetails AS (
    SELECT
        paq.Id AS QuestionId,
        paq.Title AS QuestionTitle,
        paq.OwnerUserId AS QuestionOwner,
        paa.Id AS AnswerId,
        paa.OwnerUserId AS AnswerOwner,
        paa.Score AS AnswerScore,
        paa.ViewCount AS AnswerViewCount,
        paa.CreationDate AS AnswerCreationDate,
        paa.CommentCount AS AnswerCommentCount,
        paa.UpVotes AS AnswerUpVotes,
        paa.DownVotes AS AnswerDownVotes
    FROM PostAndCommentsData paq
    LEFT JOIN PostAndCommentsData paa ON paq.AcceptedAnswerId = paa.PostId
    WHERE paq.PostTypeId = 1 AND paq.AcceptedAnswerId IS NOT NULL
),

CriticallyActivePosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        LAG(p.Score) OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS PrevPostScore,
        LEAD(p.Score) OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS NextPostScore,
        p.LastActivityDate,
        p.Tags,
        p.OwnerUserId,
        COALESCE(u.DisplayName, 'Unknown') AS OwnerDisplayName
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),

QuestionCloseHistory AS (
    SELECT 
        ph.PostId,
        ph.CreationDate,
        crt.Name AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS CloseRank
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER) -- safe cast when PostHistoryTypeId = 10
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),

QuestionsWithCloseStatus AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        qch.CloseReason,
        qch.CreationDate AS CloseDate,
        RANK() OVER (PARTITION BY p.Id ORDER BY qch.CreationDate DESC) AS CloseRank
    FROM Posts p
    LEFT JOIN QuestionCloseHistory qch ON p.Id = qch.PostId AND qch.CloseRank = 1
    WHERE p.PostTypeId = 1
),

TagExplode AS (
    SELECT
        p.Id AS QuestionId,
        TRIM(tag) AS Tag
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),

TagTopQuestions AS (
    SELECT
        te.Tag,
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY te.Tag ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore
    FROM TagExplode te
    JOIN Posts p ON te.QuestionId = p.Id
    WHERE p.PostTypeId = 1
),

FilteredTags AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(tpq.QuestionId, NULL) AS TopQuestionId,
        COALESCE(tpq.Title, 'N/A') AS TopQuestionTitle,
        COALESCE(tpq.Score, 0) AS TopQuestionScore
    FROM Tags t
    LEFT JOIN (
        SELECT Tag, QuestionId, Title, Score
        FROM TagTopQuestions
        WHERE RankByScore = 1
    ) tpq ON t.TagName = tpq.Tag
    WHERE t.Count > 100
),

UserActivityWindow AS (
    SELECT 
        u.Id,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        COUNT(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS PostsInLast30Days,
        SUM(p.Score) OVER (PARTITION BY u.Id ORDER BY p.CreationDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS ScoreInLast30Days
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate IS NOT NULL
    WHERE u.Reputation > 5000
)

SELECT
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.Views,
    tu.UpVotes,
    tu.DownVotes,
    aa.QuestionId,
    aa.QuestionTitle,
    aa.AnswerId,
    aa.AnswerScore,
    aa.AnswerUpVotes,
    cs.CloseReason,
    cs.CloseDate,
    ft.TagName,
    ft.Count AS TagUseCount,
    ft.TopQuestionTitle AS TopQuestionByTag,
    waw.PostsInLast30Days,
    waw.ScoreInLast30Days,
    -- Complex string expression showcasing tags and user badges
    CONCAT(
        'User ', COALESCE(tu.DisplayName,'[deleted]'), 
        ' holds ', tu.GoldBadges, ' gold, ', tu.SilverBadges, ' silver, and ', tu.BronzeBadges, ' bronze badges. ',
        'Top tag: ', COALESCE(ft.TagName, 'N/A'), ' with ', COALESCE(ft.Count,0), ' posts, ',
        'Top question in tag: "', COALESCE(ft.TopQuestionTitle, 'N/A'), '".'
    ) AS UserSummary,
    -- Null logic and arithmetic
    COALESCE((aa.AnswerScore::FLOAT / NULLIF(tu.Reputation,0)), 0) AS AnswerScoreToReputationRatio,
    -- Window function rank for answers per user ordered by score
    RANK() OVER(PARTITION BY aa.AnswerOwner ORDER BY aa.AnswerScore DESC) AS UserAnswerScoreRank,
    -- String manipulation to add brackets around Tags
    CASE 
        WHEN aa.QuestionTitle IS NOT NULL THEN '[' || aa.QuestionTitle || ']'
        ELSE '[No Title]'
    END AS BracketedQuestionTitle

FROM TopUsers tu

LEFT JOIN AcceptedAnswerDetails aa ON tu.Id = aa.AnswerOwner
LEFT JOIN QuestionsWithCloseStatus cs ON aa.QuestionId = cs.Id
LEFT JOIN FilteredTags ft ON ft.TopQuestionId = aa.QuestionId
LEFT JOIN UserActivityWindow waw ON waw.Id = tu.Id AND waw.PostId = aa.AnswerId

WHERE tu.RepRank <= 50
ORDER BY tu.Reputation DESC, aa.AnswerScore DESC NULLS LAST
LIMIT 100;
