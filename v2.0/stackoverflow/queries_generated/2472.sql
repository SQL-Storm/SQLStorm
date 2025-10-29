-- {"query": "2472.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1466} 
with Recursive_Tag_Hierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as TagPath,
        1 as Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        rh.TagPath || child.Id,
        rh.Level + 1
    FROM Tags child
    JOIN Posts p ON p.Tags LIKE '%' || '<' || child.TagName || '>' || '%'
    JOIN Recursive_Tag_Hierarchy rh ON rh.TagName = substring(p.Tags, 2, position('>' in p.Tags)-2)
    WHERE NOT child.Id = ANY(rh.TagPath)
),
User_Badge_Summary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
User_Posts_Answers AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
User_Activity AS (
    SELECT
        ub.UserId,
        ub.DisplayName,
        up.QuestionCount,
        up.AnswerCount,
        up.AvgPostScore,
        up.LastPostDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes
    FROM User_Badge_Summary ub
    JOIN User_Posts_Answers up ON up.UserId = ub.UserId
    JOIN Users u ON u.Id = ub.UserId
),
Top_Answered_Questions AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
Question_Duplicate_Links AS (
    SELECT
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId,
        pl.CreationDate AS LinkCreatedDate,
        u.DisplayName AS LinkCreator,
        pl.LinkTypeId
    FROM PostLinks pl
    LEFT JOIN Users u ON u.Id = (
        SELECT ph.UserId
        FROM PostHistory ph 
        WHERE ph.PostId = pl.PostId 
          AND ph.PostHistoryTypeId IN (10) -- Post Closed (often duplicates)
        ORDER BY ph.CreationDate LIMIT 1
    )
    WHERE pl.LinkTypeId = 3
),
User_Comment_Stats AS (
    SELECT
        u.Id AS UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT substring(c.Text FROM '[a-zA-Z]+'), ',' ORDER BY substring(c.Text FROM '[a-zA-Z]+')) AS CommentKeywords
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ROUND(ua.AvgPostScore::numeric,2) AS AvgPostScore,
    ua.LastPostDate,
    ua.Location,
    ua.WebsiteUrl,
    ua.Views,
    ua.UpVotes,
    ua.DownVotes,
    uc.TotalComments,
    ROUND(uc.AvgCommentScore::numeric,2) AS AvgCommentScore,
    uc.LastCommentDate,
    uc.CommentKeywords,
    td.DuplicateQuestionCount,
    td.DuplicateQuestionsSummary,
    COALESCE((
        SELECT AVG(AnswerScore) 
        FROM Top_Answered_Questions taa 
        WHERE taa.OwnerUserId = ua.UserId AND taa.AnswerRank = 1
    ), 0) AS AvgTopAnswerScore,
    COALESCE((
        SELECT MAX(ta.QuestionScore) 
        FROM Top_Answered_Questions ta 
        WHERE ta.OwnerUserId = ua.UserId
    ), 0) AS MaxQuestionScoreAuthored,
    rh.Level AS MaxTagDepth,
    rh.TagName AS DeepestTagName
FROM User_Activity ua
LEFT JOIN User_Comment_Stats uc ON uc.UserId = ua.UserId
LEFT JOIN (
    SELECT
        ph.UserId,
        COUNT(DISTINCT pl.PostId) AS DuplicateQuestionCount,
        STRING_AGG(DISTINCT q.Title, ' ; ' ORDER BY q.CreationDate DESC) AS DuplicateQuestionsSummary
    FROM PostLinks pl
    JOIN PostHistory ph ON ph.PostId = pl.PostId AND ph.PostHistoryTypeId = 10 -- Close votes, typically for duplicates
    JOIN Posts q ON q.Id = pl.PostId
    GROUP BY ph.UserId
) td ON td.UserId = ua.UserId
LEFT JOIN (
    SELECT
        DISTINCT ON (TagPath[array_length(TagPath,1)]) TagName,
        Level
    FROM Recursive_Tag_Hierarchy
    ORDER BY TagPath[array_length(TagPath,1)] DESC, Level DESC
) rh ON true
WHERE ua.Reputation > 1000 
  AND ua.TotalBadges >= 5
  AND (uc.TotalComments IS NULL OR uc.TotalComments > 10)
ORDER BY ua.Reputation DESC, ua.TotalBadges DESC
LIMIT 100;