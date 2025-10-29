-- {"query": "776.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2849}
with
q as (
  select p.Id as QuestionId,
         p.Title,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.CreationDate,
         p.Tags,
         coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select pa.Id as AnswerId,
         pa.ParentId as QuestionId,
         pa.OwnerUserId as AnswerUserId,
         pa.Score as AnswerScore,
         pa.CreationDate as AnswerCreationDate
  from Posts pa
  where pa.PostTypeId = 2
),
first_answer as (
  select a.QuestionId,
         a.AnswerId,
         a.AnswerUserId,
         a.AnswerScore,
         a.AnswerCreationDate,
         row_number() over (partition by a.QuestionId order by a.AnswerCreationDate asc, a.AnswerId asc) as rn_first,
         row_number() over (partition by a.QuestionId order by a.AnswerScore desc NULLS LAST, a.AnswerCreationDate asc, a.AnswerId asc) as rn_top
  from a
),
agg_answers as (
  select a.QuestionId,
         count(*) as total_answers,
         sum(case when a.AnswerScore > 0 then 1 else 0 end) as positive_answers,
         sum(coalesce(a.AnswerScore,0)) as sum_answer_score,
         avg(cast(a.AnswerScore as numeric)) as avg_answer_score
  from a
  group by a.QuestionId
),
votes_q as (
  select v.PostId as QuestionId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes_q,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes_q,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites_q
  from Votes v
  group by v.PostId
),
badges_u as (
  select b.UserId,
         count(*) as badge_count,
         sum(case when b.Class = 1 then 1 else 0 end) as gold_count,
         sum(case when b.Class = 2 then 1 else 0 end) as silver_count,
         sum(case when b.Class = 3 then 1 else 0 end) as bronze_count,
         max(b.Date) as last_badge_date
  from Badges b
  group by b.UserId
),
edits as (
  select ph.PostId as QuestionId,
         sum(case when ph.PostHistoryTypeId in (4,5,6,7,8,9,24) then 1 else 0 end) as edit_events,
         min(ph.CreationDate) as first_edit_at,
         max(ph.CreationDate) as last_edit_at
  from PostHistory ph
  group by ph.PostId
),
closures as (
  select ph.PostId as QuestionId,
         min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as first_closed_at,
         max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as last_reopened_at,
         sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as close_events,
         cast(nullif(regexp_replace(max(ph.Comment) filter (where ph.PostHistoryTypeId = 10), '[^0-9]', '', 'g'), '') as integer) as last_close_reason_id
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
dupe_links as (
  select pl.PostId as QuestionId,
         sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as duplicate_marks,
         sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as linked_marks
  from PostLinks pl
  group by pl.PostId
),
tag_unroll as (
  select q.QuestionId,
         unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tagname
  from q
  where q.Tags is not null and q.Tags like '<%>'
),
tag_stats as (
  select tu.QuestionId,
         count(*) as tag_count,
         string_agg(lower(tu.tagname), '|' order by lower(tu.tagname)) as tag_key
  from tag_unroll tu
  group by tu.QuestionId
),
user_stats as (
  select u.Id as UserId,
         u.Reputation,
         extract(epoch from (timestamp '2024-10-01 12:34:56' - u.CreationDate)) / 86400.0 as account_age_days,
         coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0) as net_votes_user,
         coalesce(b.badge_count,0) as badge_count,
         coalesce(b.gold_count,0) as gold_count,
         coalesce(b.silver_count,0) as silver_count,
         coalesce(b.bronze_count,0) as bronze_count,
         b.last_badge_date
  from Users u
  left join badges_u b on b.UserId = u.Id
),
question_metrics as (
  select
    q.QuestionId,
    q.Title,
    q.Score as QuestionScore,
    q.ViewCount,
    q.CreationDate as QuestionCreated,
    q.AnswerCount,
    ts.tag_count,
    ts.tag_key,
    vq.upvotes_q,
    vq.downvotes_q,
    vq.favorites_q,
    da.duplicate_marks,
    da.linked_marks,
    ed.edit_events,
    ed.first_edit_at,
    ed.last_edit_at,
    cl.first_closed_at,
    cl.last_reopened_at,
    cl.close_events,
    cl.last_close_reason_id,
    aa.total_answers,
    aa.positive_answers,
    aa.sum_answer_score,
    aa.avg_answer_score,
    fa_first.AnswerId as FirstAnswerId,
    fa_first.AnswerUserId as FirstAnswerUserId,
    fa_first.AnswerScore as FirstAnswerScore,
    fa_first.AnswerCreationDate as FirstAnswerCreated,
    fa_top.AnswerId as TopAnswerId,
    fa_top.AnswerUserId as TopAnswerUserId,
    fa_top.AnswerScore as TopAnswerScore,
    fa_top.AnswerCreationDate as TopAnswerCreated
  from q
  left join tag_stats ts on ts.QuestionId = q.QuestionId
  left join votes_q vq on vq.QuestionId = q.QuestionId
  left join dupe_links da on da.QuestionId = q.QuestionId
  left join edits ed on ed.QuestionId = q.QuestionId
  left join closures cl on cl.QuestionId = q.QuestionId
  left join agg_answers aa on aa.QuestionId = q.QuestionId
  left join first_answer fa_first on fa_first.QuestionId = q.QuestionId and fa_first.rn_first = 1
  left join first_answer fa_top on fa_top.QuestionId = q.QuestionId and fa_top.rn_top = 1
),
owner_enriched as (
  select qm.*,
         uo.DisplayName as OwnerName,
         uo.Location as OwnerLocation,
         us.Reputation as OwnerReputation,
         us.account_age_days as OwnerAccountAgeDays,
         us.net_votes_user as OwnerNetVotes,
         us.badge_count as OwnerBadgeCount,
         us.gold_count as OwnerGold,
         us.silver_count as OwnerSilver,
         us.bronze_count as OwnerBronze
  from question_metrics qm
  left join Posts p on p.Id = qm.QuestionId
  left join Users uo on uo.Id = p.OwnerUserId
  left join user_stats us on us.UserId = p.OwnerUserId
),
answerer_enriched as (
  select oe.*,
         au.DisplayName as FirstAnswererName,
         aus.Reputation as FirstAnswererReputation,
         tu.DisplayName as TopAnswererName,
         tus.Reputation as TopAnswererReputation
  from owner_enriched oe
  left join Users au on au.Id = oe.FirstAnswerUserId
  left join user_stats aus on aus.UserId = oe.FirstAnswerUserId
  left join Users tu on tu.Id = oe.TopAnswerUserId
  left join user_stats tus on tus.UserId = oe.TopAnswerUserId
),
ranked as (
  select
    ae.*,
    row_number() over (
      partition by coalesce(ae.OwnerLocation, 'UNKNOWN')
      order by
        coalesce(ae.TopAnswerScore, -999999) desc,
        coalesce(ae.QuestionScore, -999999) desc,
        ae.ViewCount desc,
        ae.QuestionId
    ) as loc_rank,
    percent_rank() over (
      partition by coalesce(ae.tag_count, 0)
      order by coalesce(ae.avg_answer_score, -1) desc
    ) as pct_by_tagcount,
    ntile(10) over (order by coalesce(ae.ViewCount,0) desc) as view_ntile
  from answerer_enriched ae
),
final_filter as (
  select r.*
  from ranked r
  where
    (coalesce(r.duplicate_marks,0) = 0 or coalesce(r.close_events,0) = 0)
    and coalesce(r.tag_count,0) between 1 and 5
    and (
      r.OwnerReputation is null
      or r.OwnerReputation > 1000
      or (r.OwnerBadgeCount >= 10 and r.OwnerNetVotes > 0)
    )
    and (
      r.FirstAnswerId is null
      or r.TopAnswerId is not null
    )
    and (
      lower(r.Title) like '%performance%'
      or lower(r.Title) like '%optimiz%'
      or lower(r.Title) like '%index%'
      or lower(r.Title) like '%query%'
      or (r.ViewCount >= 1000 and r.QuestionScore >= 0)
      or (r.favorites_q is not null and r.favorites_q >= 5)
    )
    and (
      r.first_closed_at is null
      or (r.last_reopened_at is not null and r.last_reopened_at >= r.first_closed_at)
    )
)
select
  ff.QuestionId,
  ff.Title,
  ff.QuestionScore,
  ff.ViewCount,
  ff.AnswerCount,
  coalesce(ff.total_answers,0) as total_answers,
  round(coalesce(ff.avg_answer_score,0), 2) as avg_answer_score,
  ff.positive_answers,
  ff.upvotes_q,
  ff.downvotes_q,
  ff.favorites_q,
  ff.edit_events,
  ff.duplicate_marks,
  ff.linked_marks,
  ff.tag_count,
  ff.tag_key,
  ff.OwnerName,
  ff.OwnerLocation,
  ff.OwnerReputation,
  ff.OwnerBadgeCount,
  ff.OwnerGold,
  ff.OwnerSilver,
  ff.OwnerBronze,
  ff.FirstAnswerId,
  ff.FirstAnswererName,
  ff.FirstAnswererReputation,
  ff.FirstAnswerScore,
  ff.TopAnswerId,
  ff.TopAnswererName,
  ff.TopAnswererReputation,
  ff.TopAnswerScore,
  ff.loc_rank,
  ff.pct_by_tagcount,
  ff.view_ntile,
  (
    coalesce(ff.QuestionScore,0) * 1.0
    + coalesce(ff.TopAnswerScore,0) * 1.5
    + least(coalesce(ff.ViewCount,0) / 500.0, 10)
    + coalesce(ff.upvotes_q,0) * 0.5
    - coalesce(ff.downvotes_q,0) * 0.75
    + case when ff.duplicate_marks is null or ff.duplicate_marks = 0 then 2 else -3 end
    + case when ff.favorites_q >= 10 then 5 when ff.favorites_q between 5 and 9 then 2 else 0 end
    + case when ff.OwnerReputation >= 10000 then 3 when ff.OwnerReputation >= 1000 then 1 else 0 end
    + case when ff.tag_count between 3 and 5 then 1 else 0 end
  ) as blended_quality_score,
  trim(regexp_replace(coalesce(ff.Title,''), '\s+', ' ', 'g')) as normalized_title,
  (
    select count(*) from Comments c
    where c.PostId = ff.QuestionId
      and c.CreationDate >= ff.QuestionCreated
      and c.CreationDate < coalesce(ff.last_edit_at, ff.QuestionCreated + interval '5' year)
  ) as recent_comment_count,
  case when exists (
    select 1
    from Posts pqa
    where pqa.Id = ff.QuestionId
      and pqa.AcceptedAnswerId is not null
      and exists (
        select 1 from Posts pax
        where pax.Id = pqa.AcceptedAnswerId
          and pax.OwnerUserId = (select pq2.OwnerUserId from Posts pq2 where pq2.Id = ff.QuestionId)
      )
  ) then true else false end as self_answer_accepted
from final_filter ff
order by blended_quality_score desc, ff.ViewCount desc, ff.QuestionId
limit 200;