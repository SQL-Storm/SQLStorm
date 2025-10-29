-- {"query": "255.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3519}
with recent_q as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    case when p.ClosedDate is not null then 1 else 0 end as IsClosed
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
  select
    a.ParentId as QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerUserId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate,
    row_number() over (partition by a.ParentId order by a.Score desc NULLS LAST, a.CreationDate asc) as rn_best_by_score,
    row_number() over (partition by a.ParentId order by a.CreationDate asc) as rn_first
  from Posts a
  where a.PostTypeId = 2
),
accepted as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1
    and q.AcceptedAnswerId is not null
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
    sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
    min(case when v.VoteTypeId in (2,3) then v.CreationDate end) as FirstVoteDate
  from Votes v
  group by v.PostId
),
comment_sentiment as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(case when c.Score > 0 then 1 else 0 end) as PosComments,
    sum(case when c.Score < 0 then 1 else 0 end) as NegComments,
    avg(nullif(length(c.Text),0)) as AvgCommentLen,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
tag_split as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)), '><')) as tag
  from recent_q q
),
tag_stats as (
  select
    ts.QuestionId,
    count(*) as TagCount,
    string_agg(ts.tag, ',' order by ts.tag) as TagList,
    sum(t.Count) filter (where t.Id is not null) as TagGlobalCount,
    max(case when t.IsModeratorOnly then 1 else 0 end) as HasModOnlyTag,
    max(case when t.IsRequired then 1 else 0 end) as HasRequiredTag
  from tag_split ts
  left join Tags t on lower(t.TagName) = lower(ts.tag)
  group by ts.QuestionId
),
editor_activity as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
    sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotesInHistory
  from PostHistory ph
  group by ph.PostId
),
dupe_links as (
  select
    pl.PostId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
    min(pl.CreationDate) filter (where pl.LinkTypeId = 3) as FirstDupLinkDate
  from PostLinks pl
  group by pl.PostId
),
owner as (
  select
    u.Id,
    u.Reputation,
    u.CreationDate as UserCreationDate,
    u.Views as ProfileViews,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    coalesce(nullif(trim(u.Location),''), 'Unknown') as NormalizedLocation,
    cast(date_part('year', age(timestamp '2024-10-01 12:34:56', u.CreationDate)) as integer) as AccountAgeYears
  from Users u
),
owner_badges as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    sum(case when b.TagBased = true then 1 else 0 end) as TagBadges,
    min(b.Date) as FirstBadgeDate,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
best_answer as (
  select
    a.QuestionId,
    a.AnswerId as BestAnswerId,
    a.AnswerUserId as BestAnswerUserId,
    a.AnswerScore as BestAnswerScore,
    a.AnswerCreationDate as BestAnswerCreationDate,
    case when a.rn_best_by_score = 1 then 1 else 0 end as IsTopByScore
  from answers a
  where a.rn_best_by_score = 1
),
first_answer as (
  select
    a.QuestionId,
    a.AnswerId as FirstAnswerId,
    a.AnswerCreationDate as FirstAnswerCreationDate
  from answers a
  where a.rn_first = 1
),
resolution as (
  select
    rq.QuestionId,
    ac.AcceptedAnswerId,
    ba.BestAnswerId,
    fa.FirstAnswerId,
    case when ac.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
    case when ba.BestAnswerId is not null then 1 else 0 end as HasBestByScore,
    case when fa.FirstAnswerId is not null then 1 else 0 end as HasFirstAnswer,
    case
      when ac.AcceptedAnswerId is not null then 'Accepted'
      when ba.BestAnswerId is not null then 'BestByScore'
      when fa.FirstAnswerId is not null then 'FirstOnly'
      else 'NoAnswers'
    end as ResolutionType
  from recent_q rq
  left join accepted ac on ac.QuestionId = rq.QuestionId
  left join best_answer ba on ba.QuestionId = rq.QuestionId
  left join first_answer fa on fa.QuestionId = rq.QuestionId
),
activity_windows as (
  select
    rq.QuestionId,
    rq.CreationDate as QCreated,
    va.FirstVoteDate,
    ea.FirstEditDate,
    ea.LastEditDate,
    cs.LastCommentDate,
    dl.FirstDupLinkDate,
    greatest(
      rq.CreationDate,
      coalesce(va.FirstVoteDate, timestamp '1970-01-01'),
      coalesce(ea.LastEditDate, timestamp '1970-01-01'),
      coalesce(cs.LastCommentDate, timestamp '1970-01-01'),
      coalesce(dl.FirstDupLinkDate, timestamp '1970-01-01')
    ) as LastActivityDerived
  from recent_q rq
  left join votes_agg va on va.PostId = rq.QuestionId
  left join editor_activity ea on ea.PostId = rq.QuestionId
  left join comment_sentiment cs on cs.PostId = rq.QuestionId
  left join dupe_links dl on dl.PostId = rq.QuestionId
),
scored as (
  select
    rq.QuestionId,
    rq.Title,
    rq.Tags,
    rq.Score as QScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.IsClosed,
    ts.TagCount,
    ts.TagList,
    ts.TagGlobalCount,
    ts.HasModOnlyTag,
    ts.HasRequiredTag,
    va.UpVotes,
    va.DownVotes,
    va.Favorites,
    va.BountyStarted,
    va.BountyAwarded,
    cs.CommentCount,
    cs.PosComments,
    cs.NegComments,
    cs.AvgCommentLen,
    oa.Reputation as OwnerRep,
    oa.AccountAgeYears,
    coalesce(ob.GoldBadges,0) as GoldBadges,
    coalesce(ob.SilverBadges,0) as SilverBadges,
    coalesce(ob.BronzeBadges,0) as BronzeBadges,
    coalesce(ob.TagBadges,0) as TagBadges,
    aw.QCreated,
    aw.FirstVoteDate,
    aw.FirstEditDate,
    aw.LastEditDate,
    aw.LastActivityDerived,
    r.ResolutionType,
    (
      coalesce(rq.Score,0) * 2
      + coalesce(va.UpVotes,0)
      - coalesce(va.DownVotes,0) * 2
      + coalesce(va.Favorites,0)
      + coalesce(rq.AnswerCount,0) * 1.5
      + case when rq.IsClosed = 1 then -5 else 0 end
      + least(coalesce(ts.TagCount,0), 5)
      + ln(greatest(coalesce(rq.ViewCount,0) + 1, 1))
      + coalesce(cs.PosComments,0) - coalesce(cs.NegComments,0)
      + case when ts.HasModOnlyTag = 1 then 3 else 0 end
      + case when ts.HasRequiredTag = 1 then 2 else 0 end
      + case when r.ResolutionType = 'Accepted' then 5
             when r.ResolutionType = 'BestByScore' then 3
             when r.ResolutionType = 'FirstOnly' then 1
             else -2 end
      + least(coalesce(va.BountyStarted,0) / 50.0, 10)
      + least(coalesce(va.BountyAwarded,0) / 50.0, 10)
      + least(coalesce(ob.GoldBadges,0), 10) * 0.5
      + least(coalesce(ob.SilverBadges,0), 20) * 0.25
      + least(coalesce(ob.BronzeBadges,0), 30) * 0.1
      + greatest(0, 10 - coalesce(date_part('day', timestamp '2024-10-01 12:34:56' - aw.QCreated), 0) / 7.0)
    ) as CompositeScore
  from recent_q rq
  left join tag_stats ts on ts.QuestionId = rq.QuestionId
  left join votes_agg va on va.PostId = rq.QuestionId
  left join comment_sentiment cs on cs.PostId = rq.QuestionId
  left join activity_windows aw on aw.QuestionId = rq.QuestionId
  left join resolution r on r.QuestionId = rq.QuestionId
  left join Posts qp on qp.Id = rq.QuestionId
  left join owner oa on oa.Id = qp.OwnerUserId
  left join owner_badges ob on ob.UserId = qp.OwnerUserId
),
ranked as (
  select
    s.QuestionId,
    s.Title,
    s.Tags,
    s.QScore,
    s.ViewCount,
    s.AnswerCount,
    s.IsClosed,
    s.TagCount,
    s.TagList,
    s.TagGlobalCount,
    s.HasModOnlyTag,
    s.HasRequiredTag,
    s.UpVotes,
    s.DownVotes,
    s.Favorites,
    s.BountyStarted,
    s.BountyAwarded,
    s.CommentCount,
    s.PosComments,
    s.NegComments,
    s.AvgCommentLen,
    s.OwnerRep,
    s.AccountAgeYears,
    s.GoldBadges,
    s.SilverBadges,
    s.BronzeBadges,
    s.TagBadges,
    s.QCreated,
    s.FirstVoteDate,
    s.FirstEditDate,
    s.LastEditDate,
    s.LastActivityDerived,
    s.ResolutionType,
    s.CompositeScore,
    row_number() over (order by s.CompositeScore desc NULLS LAST, s.ViewCount desc NULLS LAST) as rn,
    percent_rank() over (order by s.CompositeScore desc NULLS LAST) as pct_rank,
    ntile(10) over (order by s.CompositeScore desc NULLS LAST) as decile
  from scored s
),
null_safety as (
  select
    r.QuestionId,
    coalesce(nullif(btrim(regexp_replace(r.Title, '\s+', ' ', 'g')), ''), '(no title)') as CleanTitle,
    coalesce(r.Tags, '[]') as RawTags,
    r.QScore,
    r.ViewCount,
    r.AnswerCount,
    r.IsClosed,
    coalesce(r.TagCount, 0) as TagCount,
    coalesce(r.TagList, '') as TagList,
    coalesce(r.TagGlobalCount, 0) as TagGlobalCount,
    coalesce(r.HasModOnlyTag, 0) as HasModOnlyTag,
    coalesce(r.HasRequiredTag, 0) as HasRequiredTag,
    coalesce(r.UpVotes, 0) as UpVotes,
    coalesce(r.DownVotes, 0) as DownVotes,
    coalesce(r.Favorites, 0) as Favorites,
    coalesce(r.BountyStarted, 0) as BountyStarted,
    coalesce(r.BountyAwarded, 0) as BountyAwarded,
    coalesce(r.CommentCount, 0) as CommentCount,
    coalesce(r.PosComments, 0) as PosComments,
    coalesce(r.NegComments, 0) as NegComments,
    coalesce(r.AvgCommentLen, 0) as AvgCommentLen,
    coalesce(r.OwnerRep, 0) as OwnerRep,
    coalesce(r.AccountAgeYears, 0) as AccountAgeYears,
    r.QCreated,
    r.FirstVoteDate,
    r.FirstEditDate,
    r.LastEditDate,
    r.LastActivityDerived,
    r.ResolutionType,
    r.CompositeScore,
    r.rn,
    r.pct_rank,
    r.decile
  from ranked r
),
bucket_thresholds as (
  select
    max(case when pct_bucket = 90 then val end) as p90,
    max(case when pct_bucket = 75 then val end) as p75,
    max(case when pct_bucket = 50 then val end) as p50
  from (
    select
      CompositeScore as val,
      ntile(100) over (order by CompositeScore) as pct_bucket
    from null_safety
  ) t
),
bucketed as (
  select
    n.QuestionId,
    n.CleanTitle,
    n.RawTags,
    n.TagCount,
    n.TagList,
    n.TagGlobalCount,
    n.HasModOnlyTag,
    n.HasRequiredTag,
    n.QScore,
    n.ViewCount,
    n.AnswerCount,
    n.IsClosed,
    n.UpVotes,
    n.DownVotes,
    n.Favorites,
    n.BountyStarted,
    n.BountyAwarded,
    n.CommentCount,
    n.PosComments,
    n.NegComments,
    n.AvgCommentLen,
    n.OwnerRep,
    n.AccountAgeYears,
    n.QCreated,
    n.FirstVoteDate,
    n.FirstEditDate,
    n.LastEditDate,
    n.LastActivityDerived,
    n.ResolutionType,
    n.CompositeScore,
    n.rn,
    n.pct_rank,
    n.decile,
    case
      when n.CompositeScore >= (select percentile_cont(0.9) within group (order by CompositeScore) from null_safety) then 'Top10%'
      when n.CompositeScore >= (select percentile_cont(0.75) within group (order by CompositeScore) from null_safety) then 'Top25%'
      when n.CompositeScore >= (select percentile_cont(0.5) within group (order by CompositeScore) from null_safety) then 'Top50%'
      else 'Bottom50%'
    end as PerfBucket
  from null_safety n
),
dup_status as (
  select
    rq.QuestionId,
    case when exists (
      select 1
      from PostLinks pl
      where pl.PostId = rq.QuestionId
        and pl.LinkTypeId = 3
    ) then 1 else 0 end as IsMarkedDuplicate
  from recent_q rq
)
select
  b.QuestionId,
  b.CleanTitle,
  b.RawTags,
  b.TagCount,
  b.TagList,
  b.TagGlobalCount,
  b.HasModOnlyTag,
  b.HasRequiredTag,
  b.QScore,
  b.ViewCount,
  b.AnswerCount,
  b.IsClosed,
  d.IsMarkedDuplicate,
  b.UpVotes,
  b.DownVotes,
  b.Favorites,
  b.BountyStarted,
  b.BountyAwarded,
  b.CommentCount,
  b.PosComments,
  b.NegComments,
  b.AvgCommentLen,
  b.OwnerRep,
  b.AccountAgeYears,
  b.QCreated,
  b.FirstVoteDate,
  b.FirstEditDate,
  b.LastEditDate,
  b.LastActivityDerived,
  b.ResolutionType,
  b.CompositeScore,
  b.rn,
  b.pct_rank,
  b.decile,
  b.PerfBucket
from bucketed b
left join dup_status d on d.QuestionId = b.QuestionId
where (
    b.CompositeScore > 0
    and (
      b.TagCount between 1 and 5
      or b.HasModOnlyTag = 1
    )
    and not (b.IsClosed = 1 and d.IsMarkedDuplicate = 1)
  )
  or (
    b.ViewCount is null
    and coalesce(b.UpVotes,0) + coalesce(b.DownVotes,0) > 10
  )
order by b.CompositeScore desc NULLS LAST, b.ViewCount desc NULLS LAST
limit 250;