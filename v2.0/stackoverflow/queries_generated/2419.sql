-- {"query": "2419.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1515} 
WITH RecursiveTagCounts AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(u.Reputation, 0) AS OwnerReputation,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC) AS PostRank
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.PostTypeId = 1 AND p.Tags LIKE CONCAT('%<', t.TagName, '>%') -- Questions only with tag
    LEFT JOIN
        Users u ON u.Id = p.OwnerUserId
    WHERE
        t.TagName IS NOT NULL
),
FilteredPosts AS (
    SELECT
        r.Id, r.TagName, r.AnswerCount, r.ViewCount, r.OwnerReputation, r.OwnerUserId
    FROM
        RecursiveTagCounts r
    WHERE
        r.PostRank <= 10
),
BadgeCounts AS (
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
PostsWithBadges AS (
    SELECT
        fp.*,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges
    FROM
        FilteredPosts fp
    LEFT JOIN
        BadgeCounts bc ON bc.UserId = fp.OwnerUserId
),
UserLastVote AS (
    SELECT DISTINCT ON (v.PostId)
        v.PostId,
        v.VoteTypeId,
        v.CreationDate
    FROM
        Votes v
    WHERE
        v.VoteTypeId IN (2,3) -- UpMod or DownMod
    ORDER BY
        v.PostId,
        v.CreationDate DESC
),
CombinedVotes AS (
    SELECT 
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM
        Posts p
    LEFT JOIN
        Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
    GROUP BY
        p.Id
),
FinalResults AS (
    SELECT
        pb.Id AS PostId,
        pb.TagName,
        pb.AnswerCount,
        pb.ViewCount,
        pb.OwnerUserId,
        COALESCE(pb.OwnerReputation, 0) AS OwnerReputation,
        COALESCE(pb.GoldBadges, 0) AS GoldBadges,
        COALESCE(pb.SilverBadges, 0) AS SilverBadges,
        COALESCE(pb.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(cv.UpVotes, 0) AS UpVotes,
        COALESCE(cv.DownVotes, 0) AS DownVotes,
        p.Title,
        p.Score,
        p.CreationDate,
        COALESCE((
            SELECT COUNT(DISTINCT pl.RelatedPostId)
            FROM PostLinks pl
            WHERE pl.PostId = pb.Id
              AND pl.LinkTypeId = 3 -- Duplicate
        ), 0) AS DuplicateCount,
        -- String manipulation and null logic
        CASE 
            WHEN p.Title IS NULL OR LENGTH(TRIM(p.Title)) = 0 THEN '[No Title]'
            ELSE
                CONCAT(
                    LEFT(p.Title, 30),
                    CASE WHEN LENGTH(p.Title) > 30 THEN '...' ELSE '' END
                )
        END AS ShortTitle,
        -- Calculate an engagement score with complex calculation
        (
            (pb.ViewCount::float / NULLIF(pb.AnswerCount,0)) * 0.5
            + (pb.OwnerReputation * 0.0001)
            + (COALESCE(cv.UpVotes, 0) * 0.2)
            - (COALESCE(cv.DownVotes, 0) * 0.3)
            + (pb.GoldBadges * 2)
            + (pb.SilverBadges * 1)
            + (pb.BronzeBadges * 0.5)
        ) AS EngagementScore,
        -- Window functions for ranks by Tag
        RANK() OVER (PARTITION BY pb.TagName ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC) AS TagScoreRank,
        ROW_NUMBER() OVER (PARTITION BY pb.TagName ORDER BY pb.OwnerReputation DESC NULLS LAST) AS OwnerReputationRank
    FROM
        PostsWithBadges pb
    INNER JOIN
        Posts p ON p.Id = pb.Id
    LEFT JOIN
        CombinedVotes cv ON cv.PostId = pb.Id
),
QuestionsWithClosingStatus AS (
    SELECT
        fr.*,
        COALESCE(ch.CloseReasonName, 'Open') AS CloseStatus
    FROM
        FinalResults fr
    LEFT JOIN (
        SELECT
            ph.PostId,
            crt.Name AS CloseReasonName
        FROM
            PostHistory ph
        LEFT JOIN
            CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
        WHERE
            ph.PostHistoryTypeId = 10 -- Post Closed
            AND ph.PostId IS NOT NULL
            AND ph.Comment IS NOT NULL
    ) ch ON ch.PostId = fr.PostId
)
SELECT DISTINCT
    qws.PostId,
    qws.ShortTitle,
    qws.TagName,
    qws.AnswerCount,
    qws.ViewCount,
    qws.Score,
    qws.EngagementScore,
    qws.OwnerUserId,
    qws.OwnerReputation,
    qws.GoldBadges,
    qws.SilverBadges,
    qws.BronzeBadges,
    qws.UpVotes,
    qws.DownVotes,
    qws.DuplicateCount,
    qws.CloseStatus,
    qws.CreationDate,
    qws.TagScoreRank,
    qws.OwnerReputationRank,
    -- Correlated subquery: latest comment text for each post, with string manipulation
    (
        SELECT
            STRING_AGG(
                CASE 
                    WHEN LENGTH(c.Text) > 50 THEN CONCAT(LEFT(c.Text, 47), '...')
                    ELSE c.Text
                END, ' || '
                ORDER BY c.CreationDate DESC
            )
        FROM
            Comments c
        WHERE
            c.PostId = qws.PostId
        LIMIT 3
    ) AS TopCommentsSnippet
FROM
    QuestionsWithClosingStatus qws
WHERE
    qws.EngagementScore > 1.5
    AND (qws.CloseStatus = 'Open' OR qws.CloseStatus IS NULL)
ORDER BY
    qws.TagName ASC,
    qws.EngagementScore DESC;