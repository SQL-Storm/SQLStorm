with
params as (
    select
        date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) - interval '24 months' as from_date,
        cast('2024-10-01 12:34:56' as timestamp) as to_date,
        array['java','python','javascript','c#','sql'] as focus_tags
),
q as (
  select
      p.Id as question_id,
      p.OwnerUserId as asker_id,
      p.CreationDate as question_date,
      p.Score as question_score,
      p.ViewCount,
      p.FavoriteCount,
      p.AcceptedAnswerId,
      p.ClosedDate,
      lower(t.tag) as tag
  from Posts p
  join params pr on p.PostTypeId = 1
                and p.CreationDate between pr.from_date and pr.to_date
                and p.Tags is not null
  cross join lateral unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as t(tag)
),
tagged as (
  select
      q.*,
      count(*) over (partition by tag) as tag_volume,
      ntile(100) over (partition by tag order by question_score desc nulls last) as tag_score_percentile,
      bool_or(q.AcceptedAnswerId is not null) over (partition by question_id) as has_accept
  from q
  join params pr on (pr.focus_tags is null or array_length(pr.focus_tags,1) is null or q.tag = any(pr.focus_tags))
),
answers as (
  select
      a.ParentId as question_id,
      a.Id as answer_id,
      a.OwnerUserId as answerer_id,
      a.Score as answer_score,
      a.CreationDate as answer_date,
      (a.Id = t.AcceptedAnswerId) as is_accepted,
      row_number() over (partition by a.ParentId order by a.CreationDate) as rn_first_answer
  from Posts a
  join tagged t on a.ParentId = t.question_id
  where a.PostTypeId = 2
),
first_answer as (
  select * from answers where rn_first_answer = 1
),
first_answer_comments as (
  select
      fa.answer_id,
      count(*) filter (where c.CreationDate <= fa.answer_date + interval '1 day') as comments_1d,
      count(*) filter (where c.CreationDate <= fa.answer_date + interval '7 days') as comments_7d,
      max(c.Score) filter (where c.Score is not null) as max_comment_score
  from first_answer fa
  left join Comments c on c.PostId = fa.answer_id
  group by fa.answer_id
),
q_votes as (
  select
      v.PostId,
      sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as net_votes,
      sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
      count(*) filter (where v.VoteTypeId in (8,9)) as bounty_events,
      max(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as max_bounty
  from Votes v
  group by v.PostId
),
a_votes as (
  select
      v.PostId,
      sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as net_votes,
      count(*) filter (where v.VoteTypeId in (8,9)) as bounty_events,
      max(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as max_bounty
  from Votes v
  group by v.PostId
),
user_features as (
  select
      u.Id as user_id,
      u.Reputation,
      u.Views as profile_views,
      u.UpVotes, u.DownVotes,
      coalesce(nullif(trim(split_part(coalesce(u.Location, ''), ',', 1)), ''), 'Unknown') as region,
      cast(date_part('year', age(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate)) as integer) as account_age_years,
      case when lower(coalesce(u.WebsiteUrl,'')) like 'http://%' or lower(coalesce(u.WebsiteUrl,'')) like 'https://%' then 1 else 0 end as has_website
  from Users u
),
close_reasons as (
  select
      ph.PostId as question_id,
      max(crt.Name) filter (where ph.PostHistoryTypeId = 10 and cast(crt.Id as text) = ph.Comment) as close_reason_name,
      min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as first_closed_at
  from PostHistory ph
  left join CloseReasonTypes crt
         on ph.PostHistoryTypeId = 10
        and cast(crt.Id as text) = ph.Comment
  group by ph.PostId
),
dupe_links as (
  select pl.PostId as dup_question_id,
         pl.RelatedPostId as canonical_question_id,
         min(pl.CreationDate) as first_linked_at
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId, pl.RelatedPostId
),
user_badges as (
  select
      b.UserId as user_id,
      sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
      sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
      sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges,
      count(*) filter (where b.TagBased = true) as tag_badges
  from Badges b
  group by b.UserId
),
question_features as (
  select
      t.question_id,
      t.asker_id,
      min(t.question_date) as question_date,
      max(t.question_score) as question_score,
      max(t.ViewCount) as view_count,
      max(t.FavoriteCount) as favorite_count,
      bool_or(t.AcceptedAnswerId is not null) as has_accepted_answer,
      count(distinct t.tag) as tag_count,
      string_agg(distinct t.tag, ',' order by t.tag) as tags_flat,
      percentile_cont(0.5) within group (order by t.tag_volume) as tag_median_volume,
      max(t.tag_volume) as tag_max_volume,
      min(t.tag_score_percentile) as best_tag_percentile
  from tagged t
  group by t.question_id, t.asker_id
),
rankings as (
  select
      qf.*,
      row_number() over (order by qf.view_count desc nulls last) as rn_views,
      row_number() over (order by qf.question_score desc nulls last) as rn_score,
      row_number() over (order by coalesce(qf.favorite_count,0) desc) as rn_favs,
      dense_rank() over (order by qf.best_tag_percentile nulls last) as dr_tag_quality
  from question_features qf
),
assembled as (
  select
      r.question_id,
      r.asker_id,
      r.question_date,
      r.question_score,
      r.view_count,
      r.favorite_count,
      r.has_accepted_answer,
      r.tag_count,
      r.tags_flat,
      r.tag_median_volume,
      r.tag_max_volume,
      r.best_tag_percentile,
      r.rn_views, r.rn_score, r.rn_favs, r.dr_tag_quality,

      fa.answer_id,
      fa.answerer_id,
      fa.answer_score,
      fa.answer_date,
      fa.is_accepted as first_is_accepted,

      fac.comments_1d,
      fac.comments_7d,
      fac.max_comment_score,

      qv.net_votes as q_net_votes,
      qv.favorites as q_favorites_votes,
      qv.bounty_events as q_bounty_events,
      qv.max_bounty as q_max_bounty,

      av.net_votes as a_net_votes,
      av.bounty_events as a_bounty_events,
      av.max_bounty as a_max_bounty,

      u_ask.Reputation as asker_rep,
      u_ask.profile_views as asker_profile_views,
      u_ask.UpVotes as asker_upvotes,
      u_ask.DownVotes as asker_downvotes,
      u_ask.region as asker_region,
      u_ask.account_age_years as asker_age_years,
      u_ask.has_website as asker_has_website,

      u_ans.Reputation as answerer_rep,
      u_ans.profile_views as answerer_profile_views,
      u_ans.UpVotes as answerer_upvotes,
      u_ans.DownVotes as answerer_downvotes,
      u_ans.region as answerer_region,
      u_ans.account_age_years as answerer_age_years,
      u_ans.has_website as answerer_has_website,

      ub_ask.gold_badges as asker_gold,
      ub_ask.silver_badges as asker_silver,
      ub_ask.bronze_badges as asker_bronze,
      ub_ask.tag_badges as asker_tag_badges,

      ub_ans.gold_badges as answerer_gold,
      ub_ans.silver_badges as answerer_silver,
      ub_ans.bronze_badges as answerer_bronze,
      ub_ans.tag_badges as answerer_tag_badges,

      cr.close_reason_name,
      cr.first_closed_at,

      dl.canonical_question_id,
      dl.first_linked_at as dup_first_linked_at
  from rankings r
  left join first_answer fa on fa.question_id = r.question_id
  left join first_answer_comments fac on fac.answer_id = fa.answer_id
  left join q_votes qv on qv.PostId = r.question_id
  left join a_votes av on av.PostId = fa.answer_id
  left join user_features u_ask on u_ask.user_id = r.asker_id
  left join user_features u_ans on u_ans.user_id = fa.answerer_id
  left join user_badges ub_ask on ub_ask.user_id = r.asker_id
  left join user_badges ub_ans on ub_ans.user_id = fa.answerer_id
  left join close_reasons cr on cr.question_id = r.question_id
  left join dupe_links dl on dl.dup_question_id = r.question_id
),
final_metrics as (
  select
      a.*,
      case
        when a.view_count > 0 then round(1000.0 * coalesce(a.q_net_votes,0) / a.view_count, 3)
        else null
      end as q_votes_per_kview,
      case
        when a.answer_id is not null and a.answer_date > a.question_date
        then extract(epoch from (a.answer_date - a.question_date)) / 3600.0
        else null
      end as hours_to_first_answer,
      case
        when a.first_closed_at is not null and a.first_closed_at > a.question_date
        then extract(epoch from (a.first_closed_at - a.question_date)) / 3600.0
        else null
      end as hours_to_close,
      coalesce(a.a_net_votes,0) - coalesce(a.q_net_votes,0) as net_answer_minus_question,
      case when a.asker_region = 'Unknown' then 0 else 1 end as asker_has_region,
      (coalesce(a.asker_gold,0)*5 + coalesce(a.asker_silver,0)*3 + coalesce(a.asker_bronze,0)) as asker_badge_score,
      (coalesce(a.answerer_gold,0)*5 + coalesce(a.answerer_silver,0)*3 + coalesce(a.answerer_bronze,0)) as answerer_badge_score,
      nullif(trim(regexp_replace(coalesce(a.tags_flat,''), '\s+', ' ', 'g')), '') as tags_flat_clean,
      case
        when a.close_reason_name is null and a.dup_first_linked_at is not null then 'Duplicate (linked)'
        when a.close_reason_name is null and a.dup_first_linked_at is null and a.has_accepted_answer then 'Answered-Open'
        when a.close_reason_name is null and a.dup_first_linked_at is null and not a.has_accepted_answer then 'Unanswered-Open'
        else a.close_reason_name
      end as resolved_status
  from assembled a
),
row_scored as (
  select
      f.*,
      (
        coalesce(ln(1 + greatest(f.view_count,0)),0)
        + coalesce(f.q_votes_per_kview,0)
        + coalesce(10.0 / nullif(f.hours_to_first_answer,0), 0)
        + case when f.first_is_accepted then 2 else 0 end
        + coalesce(0.5 * f.asker_badge_score, 0)
        + coalesce(0.8 * f.answerer_badge_score, 0)
        - coalesce(0.2 * greatest(f.comments_7d - f.comments_1d, 0), 0)
      ) as composite_score
  from final_metrics f
),
partitioned as (
  select
      rs.*,
      dense_rank() over (order by coalesce(rs.asker_region,'Unknown')) as part_region,
      dense_rank() over (order by coalesce(rs.resolved_status,'Unknown')) as part_status
  from row_scored rs
)
select
    p.question_id,
    p.answer_id,
    p.asker_id,
    p.answerer_id,
    p.question_date,
    p.answer_date,
    p.resolved_status,
    p.tags_flat_clean,
    p.view_count,
    p.question_score,
    p.q_net_votes,
    p.a_net_votes,
    p.q_votes_per_kview,
    p.hours_to_first_answer,
    p.hours_to_close,
    p.first_is_accepted,
    p.composite_score,
    avg(p.composite_score) over (partition by part_region) as avg_score_by_region,
    avg(p.composite_score) over (partition by part_status) as avg_score_by_status,
    rank() over (partition by part_region order by p.composite_score desc nulls last) as rank_in_region,
    percent_rank() over (order by p.composite_score) as global_percent_rank,
    lag(p.composite_score) over (order by p.composite_score) as prev_score,
    lead(p.composite_score) over (order by p.composite_score) as next_score,
    (
      select count(*)
      from Posts p2
      where p2.PostTypeId = 1
        and p2.OwnerUserId = p.asker_id
        and p2.CreationDate between p.question_date - interval '90 days' and p.question_date
        and p2.Tags is not null
        and exists (
          select 1
          from unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) t2(tag)
          where lower(t2.tag) = any(string_to_array(coalesce(p.tags_flat_clean,''), ','))
        )
    ) as prior_similar_qs_90d,
    (
      select dl2.canonical_question_id
      from dupe_links dl2
      where dl2.dup_question_id = p.question_id
      order by dl2.first_linked_at nulls last
      limit 1
    ) as representative_canonical_id
from partitioned p
where
    (
      (p.tag_count >= 1 and (p.view_count > 0 or p.q_net_votes is not null))
      and (
        (p.hours_to_first_answer is null and p.q_net_votes <= 0)
        or (p.hours_to_first_answer between 0 and 72 and p.a_net_votes is not null)
        or (p.hours_to_first_answer > 72 and coalesce(p.a_net_votes,0) > coalesce(p.q_net_votes, -9999))
      )
    )
    and coalesce(p.asker_region, 'Unknown') <> 'Antarctica'
    and (p.close_reason_name is null or p.close_reason_name not ilike '%spam%')
order by
    p.composite_score desc nulls last,
    p.view_count desc nulls last,
    p.question_date desc
limit 500;