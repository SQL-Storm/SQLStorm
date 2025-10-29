-- {"query": "2419.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1515}
WITH RecursiveTagCounts AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(u.Reputation, 0) AS OwnerReputation,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC, p.CreationDate ASC) AS PostRank
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.PostTypeId = 1 AND p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
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
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
PostsWithBadges AS (
    SELECT
        fp.*,
        COALESCE(bc.GoldBadges, 0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges
    FROM
        FilteredPosts fp
    LEFT JOIN
        BadgeCounts bc ON bc.UserId = fp.OwnerUserId
),
UserLastVote AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        v.CreationDate
    FROM (
        SELECT
            v.*,
            ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
        FROM Votes v
        WHERE v.VoteTypeId IN (2,3)
    ) v
    WHERE v.rn = 1
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
              AND pl.LinkTypeId = 3
        ), 0) AS DuplicateCount,
        CASE 
            WHEN p.Title IS NULL OR LENGTH(TRIM(p.Title)) = 0 THEN '[No Title]'
            ELSE
                (CASE 
                    WHEN LENGTH(p.Title) > 30 THEN SUBSTRING(p.Title FROM 1 FOR 30) || '...'
                    ELSE p.Title
                 END)
        END AS ShortTitle,
        (
            (CAST(pb.ViewCount AS NUMERIC) / NULLIF(pb.AnswerCount,0)) * 0.5
            + (pb.OwnerReputation * 0.0001)
            + (COALESCE(cv.UpVotes, 0) * 0.2)
            - (COALESCE(cv.DownVotes, 0) * 0.3)
            + (pb.GoldBadges * 2)
            + (pb.SilverBadges * 1)
            + (pb.BronzeBadges * 0.5)
        ) AS EngagementScore,
        RANK() OVER (PARTITION BY pb.TagName ORDER BY p.Score DESC, p.CreationDate ASC) AS TagScoreRank,
        ROW_NUMBER() OVER (PARTITION BY pb.TagName ORDER BY pb.OwnerReputation DESC) AS OwnerReputationRank
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
            CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
        WHERE
            ph.PostHistoryTypeId = 10
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
    (
        SELECT
            STRING_AGG(
                CASE 
                    WHEN LENGTH(c.Text) > 50 THEN SUBSTRING(c.Text FROM 1 FOR 47) || '...'
                    ELSE c.Text
                END, ' || ' ORDER BY c.CreationDate DESC
            )
        FROM
            Comments c
        WHERE
            c.PostId = qws.PostId
        -- limit to 3 most recent comments: emulate by picking top 3 in a derived table
    ) AS TopCommentsSnippet
FROM
    QuestionsWithClosingStatus qws
WHERE
    qws.EngagementScore > 1.5
    AND (qws.CloseStatus = 'Open' OR qws.CloseStatus IS NULL)
ORDER BY
    qws.TagName ASC,
    qws.EngagementScore DESC;