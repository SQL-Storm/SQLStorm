-- {"query": "3009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1166} 
WITH AnswerAuthors AS (
    SELECT
        p.OwnerUserId AS AnswerUserId,
        COUNT(*) AS AnswerCount,
        AVG(p.Score) AS AvgScore
    FROM
        Posts p
    WHERE
        p.PostTypeId = 2 -- Answers
    GROUP BY
        p.OwnerUserId
),
QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.Score,
        p.OwnerUserId,
        uc.DisplayName AS OwnerDisplayName,
        ac.AnswerCount,
        ac.AvgScore,
        -- Determine if question is closed
        CASE WHEN p.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed
    FROM
        Posts p
        LEFT JOIN Users uc ON p.OwnerUserId = uc.Id
        LEFT JOIN AnswerAuthors ac ON p.Id = ac.AnswerUserId
),
RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.LastActivityDate,
        p.CommentCount,
        p.ViewCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags
    FROM
        Posts p
),
ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.ProfileImageUrl,
        u.EmailHash,
        u.CreationDate
    FROM
        Users u
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
PostHistoryCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditHistoryCount
    FROM
        PostHistory ph
    GROUP BY
        ph.PostId
),
CommentsSummary AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        STRING_AGG(c.UserDisplayName, ', ') FILTER (WHERE c.UserDisplayName IS NOT NULL) AS Commenters
    FROM
        Comments c
    GROUP BY
        c.PostId
),
LinkRelations AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM
        PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
FullPostDetails AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.Tags,
        q.Score,
        q.OwnerUserId,
        q.OwnerDisplayName,
        q.AnswerCount,
        q.AvgScore,
        q.IsClosed,
        ru.Reputation,
        ru.LastAccessDate,
        ru.Location,
        ru.AboutMe,
        ru.Views,
        ru.UpVotes,
        ru.DownVotes,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        hc.EditHistoryCount,
        cs.CommentCount AS NumComments,
        cs.Commenters,
        ar.LastActivityDate,
        ar.ViewCount,
        ar.FavoriteCount,
        ar.AcceptedAnswerId,
        ar.Title AS RecentTitle,
        ar.Tags AS RecentTags
    FROM
        QuestionStats q
        LEFT JOIN Users ru ON q.OwnerUserId = ru.Id
        LEFT JOIN UserBadgeCounts ubc ON q.OwnerUserId = ubc.UserId
        LEFT JOIN PostHistoryCounts hc ON q.QuestionId = hc.PostId
        LEFT JOIN CommentsSummary cs ON q.QuestionId = cs.PostId
        LEFT JOIN RecentActivity ar ON q.QuestionId = ar.PostId
),
FilteringQuestions AS (
    SELECT
        *
    FROM
        FullPostDetails
    WHERE
        -- Filter: Questions with at least 2 answers and an average answer score greater than 2
        AnswerCount >= 2
        AND AvgScore > 2
        -- Additional filter: questions created within the last 3 years
        AND CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 years')
        -- And questions tagged with 'sql' or 'performance'
        AND ('<sql>' = ANY (string_to_array(Tags, '><')))
)
SELECT
    fq.QuestionId,
    fq.Title,
    fq.CreationDate,
    fq.Tags,
    fq.Score,
    fq.OwnerDisplayName,
    fq.Reputation,
    fq.AnswerCount,
    fq.AvgScore,
    fq.IsClosed,
    fq.LastAccessDate,
    fq.Location,
    fq.Views,
    fq.UpVotes,
    fq.DownVotes,
    fq.GoldBadges,
    fq.SilverBadges,
    fq.BronzeBadges,
    fq.EditHistoryCount,
    fq.NumComments,
    fq.Commenters,
    fq.LastActivityDate,
    fq.ViewCount,
    fq.FavoriteCount,
    fq.AcceptedAnswerId,
    -- Join with links to find related posts of type 'Duplicate'
    EXISTS (
        SELECT 1 FROM PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
        WHERE pl.PostId = fq.QuestionId AND lt.Name = 'Duplicate'
    ) AS HasDuplicateLinks
FROM
    FilteringQuestions fq
ORDER BY
    fq.CreationDate DESC
LIMIT 100;