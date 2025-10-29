-- {"query": "165.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3408} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm
  from users u
  where u.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '24 months' from posts p)
),
question_posts as (
  select p.id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.favoritecount,
         p.commentcount,
         p.closeddate,
         p.tags,
         p.title,
         p.acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select p.id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.commentcount
  from posts p
  where p.posttypeid = 2
),
tag_split as (
  select q.id as question_id,
         unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
  from question_posts q
  where q.tags is not null and q.tags <> ''
),
hot_questions as (
  select q.id as question_id,
         q.creationdate,
         q.score,
         q.viewcount,
         q.answercount,
         q.favoritecount,
         q.commentcount,
         q.acceptedanswerid,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
         count(*) filter (where v.votetypeid = 5) as favorites_legacy,
         count(distinct a.id) as answers_total
  from question_posts q
  left join votes v on v.postid = q.id and v.creationdate >= q.creationdate - interval '1 year'
  left join answer_posts a on a.question_id = q.id
  group by q.id, q.creationdate, q.score, q.viewcount, q.answercount, q.favoritecount, q.commentcount, q.acceptedanswerid
),
duplicate_relations as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as original_post_id,
         pl.creationdate as dup_mark_date
  from postlinks pl
  where pl.linktypeid = 3
),
first_activity as (
  select u.user_id,
         min(p.creationdate) as first_post_date,
         min(c.creationdate) as first_comment_date
  from recent_users u
  left join posts p on p.owneruserid = u.user_id
  left join comments c on c.userid = u.user_id
  group by u.user_id
),
badges_rollup as (
  select b.userid as user_id,
         count(*) as total_badges,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(*) filter (where b.tagbased = 1) as tag_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_activity as (
  select u.user_id,
         count(distinct q.id) as questions_count,
         count(distinct a.id) as answers_count,
         sum(greatest(q.score,0)) as questions_score_pos,
         sum(abs(least(q.score,0))) as questions_score_neg_abs,
         sum(greatest(a.score,0)) as answers_score_pos,
         sum(abs(least(a.score,0))) as answers_score_neg_abs,
         sum(coalesce(q.viewcount,0)) as total_views,
         sum(coalesce(a.commentcount,0)) + sum(coalesce(q.commentcount,0)) as total_comment_count
  from recent_users u
  left join question_posts q on q.owneruserid = u.user_id
  left join answer_posts a on a.user_id = u.user_id
  group by u.user_id
),
user_tag_pref as (
  select q.owneruserid as user_id,
         ts.tag,
         count(*) as tag_uses,
         avg(q.score) as avg_score_per_tag
  from question_posts q
  join tag_split ts on ts.question_id = q.id
  group by q.owneruserid, ts.tag
),
top_tag_per_user as (
  select user_id, tag, tag_uses, avg_score_per_tag,
         row_number() over (partition by user_id order by tag_uses desc, avg_score_per_tag desc, tag asc) as rn
  from user_tag_pref
),
post_history_flags as (
  select ph.postid,
         max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
         max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as was_reopened,
         max(case when ph.posthistorytypeid in (52) then 1 else 0 end) as was_hot,
         max(case when ph.posthistorytypeid in (53) then 1 else 0 end) as was_unhot
  from posthistory ph
  group by ph.postid
),
recent_dups as (
  select d.dup_post_id,
         d.original_post_id,
         d.dup_mark_date,
         q.creationdate as dup_creation,
         q.owneruserid as dup_owner,
         q.title as dup_title,
         o.owneruserid as orig_owner,
         coalesce(hf.was_hot,0) as orig_was_hot
  from duplicate_relations d
  join posts q on q.id = d.dup_post_id
  join posts o on o.id = d.original_post_id
  left join post_history_flags hf on hf.postid = o.id
  where q.creationdate >= (select date_trunc('month', max(p.creationdate)) - interval '24 months' from posts p)
),
agg_votes as (
  select v.postid,
         count(*) filter (where v.votetypeid = 2) as upvotes,
         count(*) filter (where v.votetypeid = 3) as downvotes,
         count(*) filter (where v.votetypeid = 8) as bounties_started,
         sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  group by v.postid
),
user_quality as (
  select u.user_id,
         percentile_cont(0.5) within group (order by coalesce(q.viewcount,0)) as median_question_views,
         avg(coalesce(q.score,0)) as avg_question_score,
         avg(coalesce(a.score,0)) as avg_answer_score,
         stddev_pop(coalesce(a.score,0)) as stddev_answer_score,
         count(distinct q.id) filter (where q.acceptedanswerid is not null) as questions_with_accepted_answer,
         count(distinct a.id) filter (where a.score > 0) as positive_answers
  from recent_users u
  left join question_posts q on q.owneruserid = u.user_id
  left join answer_posts a on a.user_id = u.user_id
  group by u.user_id
),
post_ranks as (
  select q.id as post_id,
         q.owneruserid as user_id,
         q.creationdate,
         q.score,
         q.viewcount,
         q.answercount,
         q.favoritecount,
         rank() over (partition by q.owneruserid order by q.score desc nulls last, q.viewcount desc nulls last, q.creationdate asc) as rank_by_score,
         dense_rank() over (partition by q.owneruserid order by q.viewcount desc nulls last) as rank_by_views,
         row_number() over (partition by q.owneruserid order by coalesce(q.answercount,0) desc nulls last, q.creationdate desc) as rn_by_answers
  from question_posts q
),
string_metrics as (
  select q.id as post_id,
         length(coalesce(q.title,'')) as title_len,
         length(coalesce(q.tags,'')) as tags_len,
         (length(coalesce(q.title,'')) - length(replace(coalesce(q.title,''), ' ', ''))) + 1 as title_word_count,
         case when q.title ~* '(how|why|what|where|when)\b' then 1 else 0 end as has_wh_word
  from question_posts q
),
user_lastseen as (
  select u.id as user_id,
         max(u.lastaccessdate) as last_access
  from users u
  group by u.id
),
final_agg as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    coalesce(ua.questions_count,0) as questions_count,
    coalesce(ua.answers_count,0) as answers_count,
    coalesce(ua.total_views,0) as total_views,
    coalesce(ua.total_comment_count,0) as total_comments,
    coalesce(ua.questions_score_pos,0) - coalesce(ua.questions_score_neg_abs,0) as net_question_score,
    coalesce(ua.answers_score_pos,0) - coalesce(ua.answers_score_neg_abs,0) as net_answer_score,
    coalesce(b.total_badges,0) as total_badges,
    coalesce(b.gold_badges,0) as gold_badges,
    coalesce(b.silver_badges,0) as silver_badges,
    coalesce(b.bronze_badges,0) as bronze_badges,
    coalesce(b.tag_badges,0) as tag_badges,
    b.last_badge_date,
    tl.tag as top_tag,
    tl.tag_uses as top_tag_uses,
    tl.avg_score_per_tag as top_tag_avg_score,
    uq.median_question_views,
    uq.avg_question_score,
    uq.avg_answer_score,
    uq.stddev_answer_score,
    uq.questions_with_accepted_answer,
    uq.positive_answers,
    fa.first_post_date,
    fa.first_comment_date,
    ls.last_access,
    count(distinct rq.post_id) as ranked_questions_tracked,
    sum(case when pr.rank_by_score = 1 then 1 else 0 end) as top_scored_questions,
    sum(case when pr.rank_by_views = 1 then 1 else 0 end) as top_view_questions,
    sum(case when pr.rn_by_answers = 1 then 1 else 0 end) as top_answered_questions,
    sum(sm.title_word_count) as total_title_words,
    sum(sm.has_wh_word) as questions_with_wh_in_title,
    sum(av.upvotes) as total_upvotes_on_questions,
    sum(av.downvotes) as total_downvotes_on_questions,
    sum(av.bounties_started) as bounties_started_on_questions,
    sum(av.bounty_total) as bounty_total_on_questions,
    count(distinct rd.dup_post_id) as duplicates_marked_against_user_questions,
    count(distinct case when rd.orig_was_hot = 1 then rd.dup_post_id end) as dups_of_hot_originals
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join badges_rollup b on b.user_id = u.user_id
  left join top_tag_per_user tl on tl.user_id = u.user_id and tl.rn = 1
  left join user_quality uq on uq.user_id = u.user_id
  left join first_activity fa on fa.user_id = u.user_id
  left join user_lastseen ls on ls.user_id = u.user_id
  left join post_ranks pr on pr.user_id = u.user_id
  left join string_metrics sm on sm.post_id = pr.post_id
  left join agg_votes av on av.postid = pr.post_id
  left join recent_dups rd on rd.dup_owner = u.user_id
  left join post_ranks rq on rq.user_id = u.user_id
  group by
    u.user_id, u.displayname, u.reputation, u.creationdate,
    ua.questions_count, ua.answers_count, ua.total_views, ua.total_comment_count,
    ua.questions_score_pos, ua.questions_score_neg_abs, ua.answers_score_pos, ua.answers_score_neg_abs,
    b.total_badges, b.gold_badges, b.silver_badges, b.bronze_badges, b.tag_badges, b.last_badge_date,
    tl.tag, tl.tag_uses, tl.avg_score_per_tag,
    uq.median_question_views, uq.avg_question_score, uq.avg_answer_score, uq.stddev_answer_score,
    uq.questions_with_accepted_answer, uq.positive_answers,
    fa.first_post_date, fa.first_comment_date, ls.last_access
),
ranked_users as (
  select
    f.*,
    coalesce(nullif(f.websiteurl_norm, ''), 'N/A') as websiteurl_norm, -- passthrough from recent_users
    row_number() over (order by (coalesce(f.net_question_score,0) + coalesce(f.net_answer_score,0)) desc, f.total_views desc, f.reputation desc, f.user_created asc) as rn_overall,
    rank() over (order by f.gold_badges desc, f.total_badges desc, f.reputation desc) as rank_by_badges,
    ntile(10) over (order by coalesce(f.avg_answer_score,0) desc nulls last) as decile_by_avg_answer_score
  from final_agg f
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.user_created,
  r.questions_count,
  r.answers_count,
  r.total_views,
  r.net_question_score,
  r.net_answer_score,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.tag_badges,
  r.top_tag,
  r.top_tag_uses,
  round(coalesce(r.top_tag_avg_score,0)::numeric, 2) as top_tag_avg_score,
  round(coalesce(r.median_question_views,0)::numeric, 2) as median_question_views,
  round(coalesce(r.avg_question_score,0)::numeric, 2) as avg_question_score,
  round(coalesce(r.avg_answer_score,0)::numeric, 2) as avg_answer_score,
  round(coalesce(r.stddev_answer_score,0)::numeric, 2) as stddev_answer_score,
  r.questions_with_accepted_answer,
  r.positive_answers,
  r.first_post_date,
  r.first_comment_date,
  r.last_access,
  r.ranked_questions_tracked,
  r.top_scored_questions,
  r.top_view_questions,
  r.top_answered_questions,
  r.total_title_words,
  r.questions_with_wh_in_title,
  r.total_upvotes_on_questions,
  r.total_downvotes_on_questions,
  r.bounties_started_on_questions,
  r.bounty_total_on_questions,
  r.duplicates_marked_against_user_questions,
  r.dups_of_hot_originals,
  r.rn_overall,
  r.rank_by_badges,
  r.decile_by_avg_answer_score
from ranked_users r
where
  (r.questions_count + r.answers_count) > 0
  and coalesce(r.avg_answer_score, 0) >= (
    select avg(coalesce(avg_answer_score,0)) from ranked_users
  )
  and not exists (
    select 1
    from posts p
    where p.owneruserid = r.user_id
      and p.posttypeid = 1
      and p.closeddate is not null
      and p.creationdate >= r.user_created + interval '7 days'
  )
order by r.rn_overall
limit 200;