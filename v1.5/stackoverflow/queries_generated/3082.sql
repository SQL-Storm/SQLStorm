-- {"query": "3082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1176} 
WITH UserReputationStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(badge_counts.GoldBadges, 0) AS GoldBadges,
        COALESCE(badge_counts.SilverBadges, 0) AS SilverBadges,
        COALESCE(badge_counts.BronzeBadges, 0) AS BronzeBadges
    FROM
        Users u
    LEFT JOIN (
        SELECT
            b.UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
        FROM
            Badges b
        GROUP BY
            b.UserId
    ) badge_counts ON u.Id = badge_counts.UserId
),
PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.ContentLicense,
        jsonb_agg(DISTINCT lh.Name) FILTER (WHERE lh.Name IS NOT NULL) AS HistoryTypes,
        COUNT(DISTINCT c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        MAX(vs.CreationDate) OVER (PARTITION BY p.Id) AS LastVoteDate
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        PostHistoryTypes lh ON ph.PostHistoryTypeId = lh.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            v1.PostId,
            MAX(v1.CreationDate) AS CreationDate
        FROM
            Votes v1
        JOIN
            VoteTypes vt1 ON v1.VoteTypeId = vt1.Id
        WHERE
            vt1.Name = 'UpMod'
        GROUP BY
            v1.PostId
    ) vs ON p.Id = vs.PostId
    WHERE
        p.PostTypeId IN (1, 2)
),
TopQuestions AS (
    SELECT
        pa.PostId,
        pa.Title,
        pa.OwnerUserId,
        pa.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate DESC) AS RecencyRank
    FROM
        PostActivity pa
    WHERE
        pa.PostTypeId = 1
),
AggregatedQuestionTags AS (
    SELECT
        pt.Id AS TagId,
        pt.TagName,
        COUNT(p.Id) AS QuestionCount,
        STRING_AGG(p.Id::text, ',') AS QuestionIds
    FROM
        Tags pt
    LEFT JOIN
        Posts p ON p.Tags LIKE '%' || pt.TagName || '%'
    WHERE
        p.PostTypeId = 1
    GROUP BY
        pt.Id,
        pt.TagName
),
CombinedData AS (
    SELECT
        urs.UserId,
        urs.DisplayName,
        urs.Reputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        pa.PostId,
        pa.Title,
        pa.CreationDate AS LastQuestionDate,
        pa.OwnerUserId,
        pa.LastActivityDate,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.HistoryTypes,
        pa.LastVoteDate,
        tt.TagName,
        coalesce(at.QuestionCount, 0) AS QuestionCountPerTag,
        coalesce(at.QuestionIds, '') AS QuestionIdsPerTag
    FROM
        UserReputationStats urs
    LEFT JOIN
        TopQuestions pa ON urs.UserId = pa.OwnerUserId AND pa.RecencyRank = 1
    LEFT JOIN
        AggregatedQuestionTags at ON 1=1
    LEFT JOIN
        Tags tt ON at.TagName = tt.TagName
)
SELECT
    cd.UserId,
    cd.DisplayName,
    cd.Reputation,
    cd.GoldBadges,
    cd.SilverBadges,
    cd.BronzeBadges,
    jsonb_build_object(
        'LastQuestionTitle', cd.Title,
        'LastQuestionDate', cd.LastQuestionDate,
        'AnswerCount', cd.AnswerCount,
        'CommentCount', cd.CommentCount,
        'LastVoteDate', cd.LastVoteDate,
        'Tags', jsonb_agg(DISTINCT cd.TagName),
        'QuestionsPerTag', jsonb_object_agg(cd.TagName, cd.QuestionCountPerTag),
        'QuestionsIdsPerTag', jsonb_object_agg(cd.TagName, cd.QuestionIdsPerTag)
    ) AS UserActivitySummary
FROM
    CombinedData cd
GROUP BY
    cd.UserId,
    cd.DisplayName,
    cd.Reputation,
    cd.GoldBadges,
    cd.SilverBadges,
    cd.BronzeBadges,
    cd.Title,
    cd.LastQuestionDate,
    cd.AnswerCount,
    cd.CommentCount,
    cd.LastVoteDate;