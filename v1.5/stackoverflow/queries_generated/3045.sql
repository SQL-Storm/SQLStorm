-- {"query": "3045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1327} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPosts
    FROM Posts p
    WHERE p.PostTypeId = 1
),
ActiveAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.PostTypeId,
        a.CreationDate,
        a.OwnerUserId,
        a.ParentId,
        a.Score,
        a.AnswerCount
    FROM Posts a
    WHERE a.PostTypeId = 2 AND a.Score >= 10
),
UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.EmailHash,
        u.AccountId
    FROM Users u
),
UserBadges AS (
    SELECT
        b.UserId,
        array_agg(b.Name) FILTER (WHERE b.TagBased = FALSE) AS NamedBadges,
        array_agg(b.Name) FILTER (WHERE b.TagBased = TRUE) AS TagBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostDetails AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        p.ContentLicense,
        p.LastActivityDate,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId
    FROM Posts p
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
LinkInfo AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
HistoryCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (24, 25, 50, 52, 53, 66)) AS SignificantEdits
    FROM PostHistory ph
    GROUP BY ph.PostId
),
AggregatedData AS (
    SELECT
        pd.Id,
        pd.Title,
        pd.Tags,
        pd.Score,
        pd.AnswerCount,
        pd.ViewCount,
        pd.ContentLicense,
        pd.LastActivityDate,
        pd.CreationDate,
        pu.Reputation,
        pu.Location,
        pu.Views,
        pu.UpVotes,
        pu.DownVotes,
        pu.EmailHash,
        pu.AccountId,
        ub.NamedBadges,
        ub.TagBadges,
        cs.CommentCount,
        cs.LastCommentDate,
        li.RelatedPostId,
        li.LinkTypeName,
        hc.SignificantEdits,
        CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS PostType
    FROM PostDetails pd
    LEFT JOIN UserReputation pu ON pd.OwnerUserId = pu.UserId
    LEFT JOIN UserBadges ub ON pu.UserId = ub.UserId
    LEFT JOIN CommentStats cs ON pd.Id = cs.PostId
    LEFT JOIN LinkInfo li ON pd.Id = li.PostId
    LEFT JOIN HistoryCounts hc ON pd.Id = hc.PostId
)
SELECT
    ac.UserId,
    ac.Reputation AS UserReputation,
    ac.Location,
    ac.Views,
    ac.UpVotes,
    ac.DownVotes,
    ac.EmailHash,
    ac.AccountId,
    rd.Title AS RecentQuestionTitle,
    rd.CreationDate AS QuestionCreationDate,
    rb.AnswerId,
    rb.CreationDate AS AnswerCreationDate,
    rb.Score AS AnswerScore,
    rb.ParentId,
    uc.NamedBadges,
    uc.TagBadges,
    rs.CommentCount,
    rs.LastCommentDate,
    ld.RelatedPostId AS LinkedPostId,
    ld.LinkTypeName,
    hc.SignificantEdits
FROM Users ac
LEFT JOIN (
    SELECT
        u.Id AS UserId,
        MAX(rp.CreationDate) AS RecentQuestionCreationDate,
        MAX(rp.Title) AS RecentQuestionTitle
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId AND rp.PostTypeId = 1 AND rp.PostRank = 1
    GROUP BY u.Id
) rd ON ac.Id = rd.UserId
LEFT JOIN (
    SELECT
        a.OwnerUserId,
        a.Id AS AnswerId,
        a.CreationDate,
        a.Score,
        a.ParentId
    FROM ActiveAnswers a
) rb ON ac.Id = rb.OwnerUserId
LEFT JOIN (
    SELECT
        c.UserId,
        array_to_string(c.Names, ', ') AS NamedBadges,
        array_to_string(c.TagNames, ', ') AS TagBadges
    FROM (
        SELECT
            b.UserId,
            ARRAY_AGG(b.Name) FILTER (WHERE b.TagBased = FALSE) AS Names,
            ARRAY_AGG(b.Name) FILTER (WHERE b.TagBased = TRUE) AS TagNames
        FROM Badges b
        GROUP BY b.UserId
    ) c
) uc ON ac.Id = uc.UserId
LEFT JOIN CommentStats rs ON ac.Id = rs.PostId
LEFT JOIN (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
) ld ON ac.Id = ld.PostId
LEFT JOIN (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (24, 25, 50, 52, 53, 66)) AS SignificantEdits
    FROM PostHistory ph
    GROUP BY ph.PostId
) hc ON ac.Id = hc.PostId
WHERE ac.Reputation IS NOT NULL
ORDER BY ac.Reputation DESC
LIMIT 100;