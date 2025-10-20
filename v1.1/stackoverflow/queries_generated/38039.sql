-- {"query": "38039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2475} 
with recent_questions as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    p.Tags
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
tag_expanded as (
  select
    rq.QuestionId,
    lower(trim(tg)) as tag
  from recent_questions rq,
       unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) as tg
),
top_tags as (
  select tag, count(*) as tag_q_count
  from tag_expanded
  group by tag
  having count(*) >= 50
),
question_metrics as (
  select
    rq.QuestionId,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.AnswerCount,
    array_agg(distinct te.tag) filter (where te.tag is not null) as tags,
    count(distinct te.tag) filter (where te.tag in (select tag from top_tags)) as top_tag_hits
  from recent_questions rq
  left join tag_expanded te on te.QuestionId = rq.QuestionId
  group by rq.QuestionId, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId, rq.AnswerCount
),
answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate
  from Posts a
  where a.PostTypeId = 2
),
first_answer as (
  select
    a.QuestionId,
    min(a.AnswerCreationDate) as FirstAnswerAt
  from answers a
  group by a.QuestionId
),
question_activity as (
  select
    q.QuestionId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.AnswerCount,
    q.tags,
    q.top_tag_hits,
    fa.FirstAnswerAt,
    extract(epoch from (fa.FirstAnswerAt - q.CreationDate)) as seconds_to_first_answer
  from question_metrics q
  left join first_answer fa on fa.QuestionId = q.QuestionId
),
comment_stats as (
  select
    c.PostId as QuestionOrAnswerId,
    count(*) as comment_count,
    sum(c.Score) as comment_score_sum,
    avg(c.Score) as comment_score_avg
  from Comments c
  where c.CreationDate >= (select max(CreationDate) - interval '365 days' from Comments)
  group by c.PostId
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
    sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as bounty_started,
    sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as bounty_awarded
  from Votes v
  where v.CreationDate >= (select max(CreationDate) - interval '365 days' from Votes)
  group by v.PostId
),
dup_links as (
  select
    pl.PostId as DuplicateOfQuestionId,
    count(*) as duplicate_mark_count
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId
),
edit_events as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as edit_count,
    max(ph.CreationDate) as last_edit_at
  from PostHistory ph
  where ph.CreationDate >= (select max(CreationDate) - interval '365 days' from PostHistory)
  group by ph.PostId
),
owner_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.Views as ProfileViews,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    coalesce(b_gold.gold_cnt,0) as GoldBadges,
    coalesce(b_silver.silver_cnt,0) as SilverBadges,
    coalesce(b_bronze.bronze_cnt,0) as BronzeBadges
  from Users u
  left join (
    select UserId, count(*) as gold_cnt
    from Badges
    where Class = 1
    group by UserId
  ) b_gold on b_gold.UserId = u.Id
  left join (
    select UserId, count(*) as silver_cnt
    from Badges
    where Class = 2
    group by UserId
  ) b_silver on b_silver.UserId = u.Id
  left join (
    select UserId, count(*) as bronze_cnt
    from Badges
    where Class = 3
    group by UserId
  ) b_bronze on b_bronze.UserId = u.Id
),
q_join as (
  select
    qa.QuestionId,
    qa.CreationDate,
    qa.Score,
    qa.ViewCount,
    qa.AnswerCount,
    qa.tags,
    qa.top_tag_hits,
    qa.seconds_to_first_answer,
    os.Reputation as OwnerReputation,
    os.GoldBadges,
    os.SilverBadges,
    os.BronzeBadges,
    coalesce(vq.upvotes,0) as q_upvotes,
    coalesce(vq.downvotes,0) as q_downvotes,
    coalesce(vq.favorites,0) as q_favorites,
    coalesce(vq.bounty_started,0) as q_bounty_started,
    coalesce(vq.bounty_awarded,0) as q_bounty_awarded,
    coalesce(cs.comment_count,0) as q_comment_count,
    coalesce(cs.comment_score_sum,0) as q_comment_score_sum,
    coalesce(ee.edit_count,0) as q_edit_count,
    ee.last_edit_at,
    coalesce(dl.duplicate_mark_count,0) as duplicate_mark_count
  from question_activity qa
  left join owner_stats os on os.UserId = qa.OwnerUserId
  left join votes_agg vq on vq.PostId = qa.QuestionId
  left join comment_stats cs on cs.QuestionOrAnswerId = qa.QuestionId
  left join edit_events ee on ee.PostId = qa.QuestionId
  left join dup_links dl on dl.DuplicateOfQuestionId = qa.QuestionId
),
answers_agg as (
  select
    a.QuestionId,
    count(*) as answers_total,
    count(*) filter (where a.AnswerScore > 0) as answers_positive,
    max(a.AnswerScore) as best_answer_score,
    min(a.AnswerCreationDate) as first_answer_at,
    avg(a.AnswerScore) as avg_answer_score,
    percentile_cont(0.5) within group (order by a.AnswerScore) as median_answer_score
  from answers a
  group by a.QuestionId
),
accepted_answer as (
  select
    q.Id as QuestionId,
    acc.Id as AcceptedAnswerId,
    acc.Score as AcceptedAnswerScore,
    acc.OwnerUserId as AcceptedAnswerOwnerId
  from Posts q
  join Posts acc on acc.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
accepted_owner_stats as (
  select
    aa.QuestionId,
    os.Reputation as AcceptedOwnerReputation,
    os.GoldBadges as AcceptedOwnerGold,
    os.SilverBadges as AcceptedOwnerSilver,
    os.BronzeBadges as AcceptedOwnerBronze
  from accepted_answer aa
  left join owner_stats os on os.UserId = aa.AcceptedAnswerOwnerId
),
final as (
  select
    qj.QuestionId,
    qj.CreationDate,
    qj.Score as question_score,
    qj.ViewCount,
    qj.AnswerCount,
    qj.tags,
    qj.top_tag_hits,
    qj.seconds_to_first_answer,
    qj.OwnerReputation,
    qj.GoldBadges,
    qj.SilverBadges,
    qj.BronzeBadges,
    qj.q_upvotes,
    qj.q_downvotes,
    qj.q_favorites,
    qj.q_bounty_started,
    qj.q_bounty_awarded,
    qj.q_comment_count,
    qj.q_comment_score_sum,
    qj.q_edit_count,
    qj.last_edit_at,
    qj.duplicate_mark_count,
    coalesce(ag.answers_total,0) as answers_total,
    coalesce(ag.answers_positive,0) as answers_positive,
    coalesce(ag.best_answer_score,0) as best_answer_score,
    ag.avg_answer_score,
    ag.median_answer_score,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    aos.AcceptedOwnerReputation,
    aos.AcceptedOwnerGold,
    aos.AcceptedOwnerSilver,
    aos.AcceptedOwnerBronze
  from q_join qj
  left join answers_agg ag on ag.QuestionId = qj.QuestionId
  left join accepted_answer aa on aa.QuestionId = qj.QuestionId
  left join accepted_owner_stats aos on aos.QuestionId = qj.QuestionId
),
scored as (
  select
    f.*,
    (
      0.30 * coalesce(f.question_score,0) +
      0.15 * coalesce(f.q_upvotes - f.q_downvotes,0) +
      0.10 * coalesce(f.q_favorites,0) +
      0.10 * coalesce(f.answers_total,0) +
      0.10 * coalesce(f.best_answer_score,0) +
      0.10 * coalesce(f.ViewCount,0) / nullif((select avg(ViewCount) from recent_questions),0) +
      0.05 * coalesce(f.OwnerReputation,0) / nullif((select avg(Reputation) from Users),0) +
      0.10 * case when f.seconds_to_first_answer is not null and f.seconds_to_first_answer <= 3600 then 1 else 0 end
    ) as engagement_score
  from final f
)
select
  s.QuestionId,
  s.CreationDate,
  s.tags,
  s.ViewCount,
  s.question_score,
  s.q_upvotes,
  s.q_downvotes,
  s.q_favorites,
  s.answers_total,
  s.best_answer_score,
  s.seconds_to_first_answer,
  s.OwnerReputation,
  s.GoldBadges,
  s.SilverBadges,
  s.BronzeBadges,
  s.q_edit_count,
  s.duplicate_mark_count,
  round(s.engagement_score::numeric, 3) as engagement_score
from scored s
where s.top_tag_hits >= 1
order by s.engagement_score desc nulls last, s.ViewCount desc
limit 200;