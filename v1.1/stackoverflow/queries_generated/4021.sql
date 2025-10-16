-- {"query": "4021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1443} 
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
TopQ as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId = 1 and p.Score is not null and p.OwnerUserId is not null
),
TopAnswersPerQuestion as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName
    from Posts a
    inner join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        count(distinct a.AnswerId) as AnswersCount,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerScore) as MinAnswerScore,
        avg(a.AnswerScore) as AvgAnswerScore
    from Posts q
    left join TopAnswersPerQuestion a on q.Id = a.QuestionId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        min(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
QuestionCloseReasonStats as (
    select
        q.Id as QuestionId,
        crt.Name as CloseReasonName,
        q.Score,
        q.ViewCount,
        phc.CloseReasonId
    from Posts q
    inner join ClosedQuestionsWithReason phc on q.Id = phc.PostId
    left join CloseReasonTypes crt on phc.CloseReasonId = crt.Id
    where q.PostTypeId = 1
),
WindowAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRankByScore,
        rank() over (partition by a.ParentId order by a.CreationDate asc) as AnswerRankByDate
    from Posts a
    where a.PostTypeId = 2
),
AnswerSummary as (
    select
        w.QuestionId,
        count(w.AnswerId) as TotalAnswers,
        sum(case when w.AnswerRankByScore = 1 then 1 else 0 end) as TopScoreAnswers,
        sum(case when w.AnswerRankByDate = 1 then 1 else 0 end) as FirstAnswers
    from WindowAnswers w
    group by w.QuestionId
),
ComplexUserDerived as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.Location,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        rank() over (order by u.Reputation desc, u.Views desc nulls last) as ReputationRank,
        ntile(4) over (order by u.CreationDate) as CreationQuartile,
        -- String length safe check with COALESCE
        length(coalesce(u.Location, '')) as LocationLength
    from Users u
    left join UserBadgeCounts ubc on u.Id = ubc.UserId
)
select
    qas.QuestionId,
    qas.Title,
    u.DisplayName as QuestionOwner,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswersCount,
    qas.MaxAnswerScore,
    qas.MinAnswerScore,
    round(qas.AvgAnswerScore,2) as AvgAnswerScore,
    qcr.CloseReasonName,
    ans.TotalAnswers,
    ans.TopScoreAnswers,
    ans.FirstAnswers,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.TagBasedBadges,
    cu.ReputationRank,
    cu.CreationQuartile,
    cu.Location,
    cu.LocationLength,
    -- Find earliest comment by this question owner on their own question, if any
    (select min(c.CreationDate)
     from Comments c
     where c.PostId = qas.QuestionId and c.UserId = qas.OwnerUserId
    ) as FirstOwnerCommentDate,
    -- Complex predicate with NULL-safe coalesce and regexp_replace to count tags in Tags column
    array_length(string_to_array(regexp_replace(qas.Title || coalesce(qas.Tags,'<unknown>'), '<[^>]+>', '', 'g'), ' '), 1) as WordCountEstimated,
    -- String concatenation example: Owner's DisplayName with first badge name concatenated (if any)
    concat(cu.DisplayName, ' - ', coalesce(
        (select top 1 b.Name from Badges b where b.UserId = cu.Id order by b.Date asc),
        'No Badges')) as UserBadgeSummary
from QuestionAnswerStats qas
left join QuestionCloseReasonStats qcr on qas.QuestionId = qcr.QuestionId
left join AnswerSummary ans on qas.QuestionId = ans.QuestionId
left join ComplexUserDerived cu on qas.OwnerUserId = cu.Id
where
    (qas.AnswersCount > 3 or qas.QuestionScore > 10) and
    (qcr.CloseReasonName is null or qcr.CloseReasonName not in ('Duplicate', 'Exact Duplicate'))
order by
    qas.QuestionScore desc,
    ans.TotalAnswers desc,
    cu.ReputationRank asc
limit 100;