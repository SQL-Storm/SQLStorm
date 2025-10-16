-- {"query": "844.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1587} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        u.Reputation
    from Tags t
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    left join Users u on p.OwnerUserId = u.Id
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
UserBadgeAggregates as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreDenseRank
    from Posts p
    where p.PostTypeId in (1, 2) -- Questions and Answers only
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.ViewCount as AnswerViews,
        a.CreationDate as AnswerCreation,
        u.DisplayName as QuestionOwner,
        u.Reputation as QuestionOwnerRep,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.Score > (
        select avg(suba.Score)
        from Posts suba
        where suba.ParentId = q.Id and suba.PostTypeId = 2
    )
    left join Users u on q.OwnerUserId = u.Id
    left join UserBadgeAggregates uba on uba.UserId = u.Id
    where q.PostTypeId = 1
      and q.Score > 10
      and q.ViewCount > 1000
),
CombinedPostVotes as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
PostHistoryCloseStatus as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
FinalResults as (
    select
        tq.QuestionId,
        tq.Title,
        tq.Tags,
        tq.QuestionScore,
        tq.QuestionViews,
        tq.QuestionCreation,
        tq.AnswerId,
        tq.AnswerScore,
        tq.AnswerViews,
        tq.AnswerCreation,
        coalesce(tq.QuestionOwner, 'Community') as QuestionOwner,
        coalesce(tq.QuestionOwnerRep, 0) as QuestionOwnerReputation,
        coalesce(tq.GoldBadges, 0) as GoldBadges,
        coalesce(tq.SilverBadges, 0) as SilverBadges,
        coalesce(tq.BronzeBadges, 0) as BronzeBadges,
        cv.UpVotes,
        cv.DownVotes,
        cv.Favorites,
        cv.TotalVotes,
        phcs.ClosedDate,
        phcs.ReopenedDate,
        crt.Name as CloseReasonName,
        row_number() over (partition by tq.QuestionId order by tq.AnswerScore desc nulls last) as AnswerRank,
        length(tq.Title) as TitleLength,
        (case when tq.QuestionViews > 10000 then 'High View' else 'Normal View' end) as ViewCategory,
        regexp_replace(tq.Tags, '[<>]', '', 'g') as CleanTags,
        upper(coalesce(tq.QuestionOwner, 'COMMUNITY')) as UpperOwnerName
    from TopQuestionsWithAnswers tq
    left join CombinedPostVotes cv on cv.PostId = tq.QuestionId
    left join PostHistoryCloseStatus phcs on phcs.PostId = tq.QuestionId
    left join CloseReasonTypes crt on crt.Id::varchar = phcs.CloseReasonId
    where tq.AnswerId is not null
)
select *
from FinalResults
where AnswerRank = 1
  and (
    (GoldBadges > 0 and SilverBadges > 5)
    or (QuestionOwnerReputation > 10000 and QuestionScore > 50)
  )
union all
select
    p.Id as QuestionId,
    p.Title,
    p.Tags,
    p.Score as QuestionScore,
    p.ViewCount as QuestionViews,
    p.CreationDate as QuestionCreation,
    null::int as AnswerId,
    null::int as AnswerScore,
    null::int as AnswerViews,
    null::timestamp as AnswerCreation,
    u.DisplayName as QuestionOwner,
    u.Reputation as QuestionOwnerReputation,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    cv.UpVotes,
    cv.DownVotes,
    cv.Favorites,
    cv.TotalVotes,
    phcs.ClosedDate,
    phcs.ReopenedDate,
    crt.Name as CloseReasonName,
    0 as AnswerRank,
    length(p.Title) as TitleLength,
    (case when p.ViewCount > 10000 then 'High View' else 'Normal View' end) as ViewCategory,
    regexp_replace(p.Tags, '[<>]', '', 'g') as CleanTags,
    upper(coalesce(u.DisplayName, 'COMMUNITY')) as UpperOwnerName
from Posts p
left join Users u on u.Id = p.OwnerUserId
left join CombinedPostVotes cv on cv.PostId = p.Id
left join PostHistoryCloseStatus phcs on phcs.PostId = p.Id
left join CloseReasonTypes crt on crt.Id::varchar = phcs.CloseReasonId
where p.PostTypeId = 1
  and p.Score > 100
  and p.ViewCount > 5000
  and not exists (
      select 1 from Posts a where a.ParentId = p.Id and a.Score > 10
  )
order by QuestionScore desc, QuestionViews desc, AnswerScore desc nulls last
limit 100;