-- {"query": "66.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3197}
with
q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.Score as QScore,
    p.ViewCount,
    p.CreationDate as QCreated,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    p.Tags,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerRep,
    string_to_array(substring(p.Tags from 2 for greatest(char_length(p.Tags)-2,0)), '><') as tag_arr
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
),
answers as (
  select
    a.ParentId as QuestionId,
    count(*) as AnswerCnt,
    avg(a.Score) as AvgAnswerScore,
    max(a.Score) as MaxAnswerScore,
    sum(case when a.Id = q2.AcceptedAnswerId then 1 else 0 end) as HasAccepted
  from Posts a
  join Posts q2 on q2.Id = a.ParentId and q2.PostTypeId = 1
  where a.PostTypeId = 2
  group by a.ParentId
),
first_last_activity as (
  select
    ph.PostId,
    min(ph.CreationDate) as FirstEvent,
    max(ph.CreationDate) as LastEvent,
    sum(case when ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35) then 1 else 0 end) as ModerationEvents
  from PostHistory ph
  group by ph.PostId
),
votes_by_type as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    count(*) as TotalVotes,
    min(v.CreationDate) as FirstVote,
    max(v.CreationDate) as LastVote
  from Votes v
  group by v.PostId
),
comment_stats as (
  select
    c.PostId,
    count(*) as CommentCount,
    avg(c.Score) as AvgCommentScore,
    max(c.Score) as MaxCommentScore,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
  from Comments c
  group by c.PostId
),
tag_expanded as (
  select
    q.QuestionId,
    trim(both ' ' from lower(t.tag)) as tag
  from q
  cross join lateral (
    select unnest(q.tag_arr) as tag
  ) t
),
top_tags as (
  select
    te.tag,
    count(distinct te.QuestionId) as QsWithTag,
    sum(coalesce(a.AnswerCnt,0)) as AnswersOnTag,
    avg(coalesce(a.AvgAnswerScore,0)) as AvgAnsScoreOnTag
  from tag_expanded te
  left join answers a on a.QuestionId = te.QuestionId
  group by te.tag
  having count(distinct te.QuestionId) >= 5
),
user_activity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    sum(case when p.PostTypeId = 1 then 1 else 0 end) as Questions,
    sum(case when p.PostTypeId = 2 then 1 else 0 end) as Answers,
    sum(coalesce(p.Score,0)) as TotalPostScore,
    sum(coalesce(vs.UpVotes,0)) as TotalPostUpVotes,
    sum(coalesce(vs.DownVotes,0)) as TotalPostDownVotes
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join votes_by_type vs on vs.PostId = p.Id
  group by u.Id, u.DisplayName, u.Reputation
),
hot_candidates as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.OwnerRep,
    q.QScore,
    q.ViewCount,
    coalesce(a.AnswerCnt,0) as AnswerCnt,
    coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(a.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(a.HasAccepted,0) as HasAccepted,
    coalesce(v.UpVotes,0) as UpVotes,
    coalesce(v.DownVotes,0) as DownVotes,
    coalesce(v.Favorites,0) as Favorites,
    coalesce(v.BountyTotal,0) as BountyTotal,
    coalesce(c.CommentCount,0) as CommentCount,
    coalesce(c.AvgCommentScore,0) as AvgCommentScore,
    fl.FirstEvent,
    fl.LastEvent,
    fl.ModerationEvents,
    q.QCreated,
    extract(epoch from (coalesce(v.LastVote, q.QCreated) - q.QCreated))/3600.0 as HoursToLastVote,
    extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - q.QCreated))/3600.0 as AgeHours,
    q.Tags
  from q
  left join answers a on a.QuestionId = q.QuestionId
  left join votes_by_type v on v.PostId = q.QuestionId
  left join comment_stats c on c.PostId = q.QuestionId
  left join first_last_activity fl on fl.PostId = q.QuestionId
),
scored as (
  select
    h.*,
    case
      when h.OwnerRep is null then 0
      else ln(greatest(h.OwnerRep, 1))
    end as OwnerRepLog,
    case when h.AgeHours <= 0 then 0.0 else (h.UpVotes - h.DownVotes) / nullif(h.AgeHours,0) end as NetVotesPerHour,
    case when h.AgeHours <= 0 then 0.0 else h.ViewCount / nullif(h.AgeHours,0) end as ViewsPerHour,
    case when h.AnswerCnt = 0 then 0.0 else h.Favorites / nullif(h.AnswerCnt,0) end as FavoritesPerAnswer,
    case when h.CommentCount = 0 then 0.0 else h.AvgCommentScore end as AvgCommentScoreNN,
    (coalesce(h.UpVotes,0) * 1.0 + coalesce(h.Favorites,0) * 0.7 + coalesce(h.ViewCount,0) * 0.001 + coalesce(h.BountyTotal,0) * 0.02
      - coalesce(h.DownVotes,0) * 0.6 - coalesce(h.ModerationEvents,0) * 1.5
      + case when h.HasAccepted > 0 then 3 else 0 end
    ) as CompositeRaw,
    case
      when h.Tags ilike '%<discussion>%' then 0.85
      when h.Tags ilike '%<homework>%' then 0.7
      else 1.0
    end as TagBoost
  from hot_candidates h
),
ranked as (
  select
    s.*,
    (s.CompositeRaw * s.TagBoost) +
    (coalesce(s.NetVotesPerHour,0) * 5) +
    (coalesce(s.ViewsPerHour,0) * 0.5) +
    (coalesce(s.FavoritesPerAnswer,0) * 2) +
    (coalesce(s.AvgAnswerScore,0) * 0.3) +
    (coalesce(s.OwnerRepLog,0) * 0.4) as FinalScore,
    row_number() over (order by
      ((s.CompositeRaw * s.TagBoost) +
       coalesce(s.NetVotesPerHour,0) * 5 +
       coalesce(s.ViewsPerHour,0) * 0.5 +
       coalesce(s.FavoritesPerAnswer,0) * 2 +
       coalesce(s.AvgAnswerScore,0) * 0.3 +
       coalesce(s.OwnerRepLog,0) * 0.4) desc,
      s.QScore desc,
      s.ViewCount desc
    ) as RN,
    dense_rank() over (order by s.OwnerRep desc nulls last) as OwnerRepRank,
    ntile(10) over (order by coalesce(s.ViewCount,0) desc) as ViewDecile,
    sum(coalesce(s.UpVotes,0)) over (order by s.QuestionId rows between unbounded preceding and current row) as RunningUpvotes
  from scored s
),
tag_agg as (
  select
    te.QuestionId,
    string_agg(te.tag, ',' order by te.tag) as tag_list,
    max(case when te.tag = 'sql' then 1 else 0 end) as has_sql,
    max(case when te.tag = 'postgresql' then 1 else 0 end) as has_pg
  from tag_expanded te
  group by te.QuestionId
),
rep_buckets as (
  select
    ua.UserId,
    case
      when ua.Reputation < 100 then 'New'
      when ua.Reputation < 1000 then 'Rookie'
      when ua.Reputation < 10000 then 'Experienced'
      else 'Veteran'
    end as RepBucket
  from user_activity ua
),
final_candidates as (
  select
    r.QuestionId,
    r.Title,
    r.OwnerUserId,
    r.OwnerName,
    r.OwnerRep,
    rb.RepBucket,
    coalesce(ta.tag_list, '') as TagsCSV,
    r.QScore,
    r.ViewCount,
    r.AnswerCnt,
    r.HasAccepted,
    r.UpVotes,
    r.DownVotes,
    r.Favorites,
    r.BountyTotal,
    r.CommentCount,
    r.AvgAnswerScore,
    r.AvgCommentScoreNN as AvgCommentScore,
    r.FirstEvent,
    r.LastEvent,
    r.ModerationEvents,
    r.QCreated,
    r.AgeHours,
    r.NetVotesPerHour,
    r.ViewsPerHour,
    r.FavoritesPerAnswer,
    r.OwnerRepLog,
    r.CompositeRaw,
    r.TagBoost,
    r.FinalScore,
    r.RN,
    r.OwnerRepRank,
    r.ViewDecile,
    r.RunningUpvotes,
    case when coalesce(ta.has_sql,0) = 1 or coalesce(ta.has_pg,0) = 1 then 1 else 0 end as IsDBRelated,
    r.Tags
  from ranked r
  left join tag_agg ta on ta.QuestionId = r.QuestionId
  left join rep_buckets rb on rb.UserId = r.OwnerUserId
),
dupe_links as (
  select
    pl.PostId as QuestionId,
    sum(case when (lt.Name = 'Duplicate' or pl.LinkTypeId = 3) then 1 else 0 end) as DuplicateLinks,
    sum(case when (lt.Name = 'Linked' or pl.LinkTypeId = 1) then 1 else 0 end) as LinkedLinks
  from PostLinks pl
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
closed_reasons as (
  select
    ph.PostId,
    max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonId,
    max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastClosedAt
  from PostHistory ph
  group by ph.PostId
),
with_null_logic as (
  select
    fc.*,
    dl.DuplicateLinks,
    dl.LinkedLinks,
    cr.LastCloseReasonId,
    cr.LastClosedAt,
    case
      when cr.LastCloseReasonId is null and coalesce(fc.ModerationEvents,0) = 0 then 'Clean'
      when cr.LastCloseReasonId is not null then 'Closed'
      else 'Moderated'
    end as StatusLabel,
    nullif(fc.ViewCount, 0) as ViewsNN,
    coalesce(dl.DuplicateLinks, 0) + coalesce(dl.LinkedLinks, 0) as TotalLinks,
    case when coalesce(dl.DuplicateLinks,0) > 0 then 1 else 0 end as HasDupes
  from final_candidates fc
  left join dupe_links dl on dl.QuestionId = fc.QuestionId
  left join closed_reasons cr on cr.PostId = fc.QuestionId
),
dedup as (
  select distinct on (w.QuestionId)
    w.*
  from with_null_logic w
  order by w.QuestionId, w.FinalScore desc
),
filtered as (
  select
    d.*,
    exists (
      select 1
      from Comments c
      where c.PostId = d.QuestionId
        and c.Text ilike '%thanks%'
    ) as HasThanksComment,
    exists (
      select 1
      from Votes v
      where v.PostId = d.QuestionId
        and v.VoteTypeId in (8,9)
    ) as HasBountyActivity
  from dedup d
  where d.AgeHours > 1
    and (d.IsDBRelated = 1 or d.Favorites >= 1 or d.BountyTotal > 0)
    and coalesce(d.DownVotes,0) <= coalesce(d.UpVotes,0)
)
select *
from (
  select
    f.QuestionId,
    left(coalesce(f.Title, ''), 200) as Title,
    coalesce(f.OwnerName, '[unknown]') as OwnerName,
    coalesce(f.RepBucket, 'Unknown') as RepBucket,
    f.QScore,
    f.ViewCount,
    f.AnswerCnt,
    f.HasAccepted,
    f.UpVotes,
    f.DownVotes,
    f.Favorites,
    f.BountyTotal,
    f.CommentCount,
    f.AvgAnswerScore,
    f.AvgCommentScore,
    coalesce(f.DuplicateLinks,0) as DuplicateLinks,
    coalesce(f.LinkedLinks,0) as LinkedLinks,
    coalesce(f.TotalLinks,0) as TotalLinks,
    coalesce(f.StatusLabel,'Unknown') as StatusLabel,
    coalesce(f.TagsCSV,'') as TagsCSV,
    cast(round(cast(f.FinalScore as numeric), 3) as double precision) as FinalScore,
    f.RN as RankOverall,
    f.OwnerRepRank,
    f.ViewDecile,
    f.RunningUpvotes,
    f.HasThanksComment,
    f.HasBountyActivity,
    f.QCreated,
    f.FirstEvent,
    f.LastEvent,
    f.LastClosedAt,
    row_number() over (order by f.FinalScore desc, f.QScore desc, f.ViewCount desc) as _rn
  from filtered f
) t
where t._rn <= 200;