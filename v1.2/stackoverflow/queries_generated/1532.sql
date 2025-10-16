-- {"query": "1532.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1541} 
with RecursiveBadgeCounts as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
), QuestionAnswerSummary as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate as QuestionDate,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score), 0) as AnswerScoreTotal,
        max(a.Score) filter (where a.Score is not null) as MaxAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.OwnerUserId, q.Title, q.CreationDate
), UserRanking as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        rank() over (order by u.Reputation desc, ufks.AnsweredQuestions desc nulls last) as ReputationRank,
        row_number() over (partition by 1 order by ufks.AnsweredQuestions desc nulls last) as AnsweredRank
    from Users u
    left join RecursiveBadgeCounts ubc on u.Id = ubc.UserId
    left join (
        select OwnerUserId, count(distinct Id) as AnsweredQuestions
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) ufks on u.Id = ufks.OwnerUserId
), AnswerAcceptedFlags as (
    select
        a.Id as AnswerId,
        case when exists (
            select 1
            from Posts q2
            where q2.AcceptedAnswerId = a.Id
        ) then 1 else 0 end as IsAcceptedAnswer
    from Posts a
    where a.PostTypeId = 2
), ComplexComments as (
    select
        c.PostId,
        c.Id as CommentId,
        c.UserId,
        u.DisplayName as CommentUserName,
        c.CreationDate,
        length(c.Text) as CommentLength,
        upper(c.Text) as UpperCommentText,
        coalesce(nullif(regexp_replace(c.Text, '\W', '', 'g'), ''), 'NoLetters') as LettersOnlyText,
        case
            when c.Score is null then 0
            else c.Score
        end as AdjustedScore
    from Comments c
    left join Users u on c.UserId = u.Id
    where strpos(upper(c.Text), 'SELECT') > 0 or strpos(lower(c.Text), 'error') > 0
), LatestPostHistoryEdits as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.Id as PostHistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text,
        ph.ContentLicense
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Title Body Tags edits
    order by ph.PostId, ph.CreationDate desc
), UserReputationWindow as (
    select
        UserId,
        Reputation,
        CreationDate,
        lag(Reputation) over (partition by UserId order by CreationDate) as PrevRep,
        Reputation - lag(Reputation) over (partition by UserId order by CreationDate) as RepChange
    from (
        select
            Id as UserId,
            Reputation,
            CreationDate
        from Users
    ) sub
),
DuplicatedPostsUnionLinks as (
    select pl.PostId from PostLinks pl where pl.LinkTypeId=3 -- Duplicate links as first
    union
    select pl.RelatedPostId from PostLinks pl where pl.LinkTypeId=3 -- Duplicate links as second
),
BenchmarkDataset as (
    select qas.QuestionId, qas.Title,
        uq.DisplayName as QuestionOwner,
        uq.Reputation,
        qas.AnswerCount,
        qas.AnswerScoreTotal,
        qas.MaxAnswerScore,
        rsp.PostHistoryTypeId,
        rsp.CreationDate as LastEditDate,
        rsp.UserDisplayName as EditorName,
        acf.IsAcceptedAnswer,
        count(distinct cm.CommentId) as RelatedSelectiveComments,
        sum(case when cm.AdjustedScore>3 then 1 else 0 end) as HighlyReviewedComments,
        CASE 
            WHEN qas.AnswerCount > 0 THEN Round(qas.AnswerScoreTotal/qas.AnswerCount::float,2)
            ELSE 0
        END as AvgAnswerScore,
        (uq.GoldBadges*100 + uq.SilverBadges*10 + uq.BronzeBadges) as CompositeBadgeScore,
        sum(case when pf.RepChange > 50 then 1 else 0 end) as ReputationJumps
    from QuestionAnswerSummary qas
    left join UserRanking uq on uq.UserId = qas.OwnerUserId
    left join LatestPostHistoryEdits rsp on rsp.PostId = qas.QuestionId
    left join Posts pAns on pAns.ParentId = qas.QuestionId and pAns.PostTypeId=2
    left join AnswerAcceptedFlags acf on acf.AnswerId = pAns.Id
    left join ComplexComments cm on cm.PostId = qas.QuestionId or cm.PostId = pAns.Id
    left join UserReputationWindow pf on pf.UserId = uq.UserId and pf.CreationDate > qas.QuestionDate
    where qas.QuestionId not in (select PostId from DuplicatedPostsUnionLinks)
    group by qas.QuestionId, qas.Title, uq.DisplayName, uq.Reputation, uGBT.GoldBadges, uGBT.SilverBadges, uGBT.BronzeBadges,
        qas.AnswerCount, qas.AnswerScoreTotal, qas.MaxAnswerScore, rsp.PostHistoryTypeId, rsp.CreationDate, rsp.UserDisplayName, acf.IsAcceptedAnswer
)

select
    bd.QuestionId,
    substring(bd.Title from 1 for 70) as TitleSnippet,
    bd.QuestionOwner,
    bd.Reputation,
    bd.AnswerCount,
    bd.AvgAnswerScore,
    bd.MaxAnswerScore,
    bd.CompositeBadgeScore,
    bd.RelatedSelectiveComments,
    bd.HighlyReviewedComments,
    bd.LastEditDate,
    bd.EditorName,
    decode(bd.IsAcceptedAnswer, 1, 'Yes', 'No') as HasAcceptedAnswer,
    bd.ReputationJumps
from BenchmarkDataset bd
where 
    bd.AnswerCount > 3 
    and bd.CompositeBadgeScore > 10
    and bd.RelatedSelectiveComments > 0
order by bd.CompositeBadgeScore desc, bd.AvgAnswerScore desc, bd.ReputationJumps desc
limit 100;