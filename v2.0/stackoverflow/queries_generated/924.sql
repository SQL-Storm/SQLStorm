-- {"query": "924.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3624} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as country_hint,
           dense_rank() over (order by u.creationdate desc) as signup_rank
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from users)
),
user_badge_stats as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
posts_enriched as (
    select p.id,
           p.posttypeid,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.favoritecount,
           p.commentcount,
           p.answercount,
           p.title,
           p.tags,
           p.acceptedanswerid,
           p.parentid,
           p.closeddate,
           p.lastactivitydate,
           coalesce(p.ownerdisplayname, u.displayname) as owner_name,
           u.reputation as owner_rep
    from posts p
    left join users u on u.id = p.owneruserid
),
questions as (
    select pe.*
    from posts_enriched pe
    where pe.posttypeid = 1
),
answers as (
    select pe.*
    from posts_enriched pe
    where pe.posttypeid = 2
),
q_tag_array as (
    select q.id as question_id,
           q.owneruserid,
           q.creationdate,
           q.score,
           q.viewcount,
           q.favoritecount,
           q.commentcount,
           q.answercount,
           q.title,
           q.tags,
           string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><') as taglist
    from questions q
),
q_with_primary_tag as (
    select question_id,
           owneruserid,
           creationdate,
           score,
           viewcount,
           favoritecount,
           commentcount,
           answercount,
           title,
           tags,
           nullif(taglist[1], '') as primary_tag,
           cardinality(taglist) as tag_count
    from q_tag_array
),
q_activity as (
    select q.question_id,
           count(distinct c.id) as comments_on_q,
           count(distinct a.id) as answers_count,
           sum(coalesce(a.score,0)) as answers_score_sum,
           max(a.score) as max_answer_score,
           count(distinct case when v.votetypeid = 2 then v.id end) as upvotes_on_q,
           count(distinct case when v.votetypeid = 3 then v.id end) as downvotes_on_q,
           count(distinct case when v.votetypeid = 5 then v.id end) as favorites_on_q
    from q_with_primary_tag q
    left join comments c on c.postid = q.question_id
    left join answers a on a.parentid = q.question_id
    left join votes v on v.postid = q.question_id
    group by q.question_id
),
answerer_stats as (
    select a.parentid as question_id,
           count(*) filter (where a.owneruserid is not null) as answered_by_registered,
           count(*) filter (where a.owneruserid is null) as answered_by_unregistered,
           count(distinct a.owneruserid) filter (where a.owneruserid is not null) as distinct_answerers,
           avg(a.score) as avg_answer_score,
           sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted_answer
    from answers a
    join questions q on q.id = a.parentid
    group by a.parentid
),
close_reasons as (
    select ph.postid as question_id,
           max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_text,
           max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopen_date,
           max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_close_date
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select pl.postid as question_id,
           count(*) filter (where pl.linktypeid = 3) as duplicate_marks,
           count(*) filter (where pl.linktypeid = 1) as linked_marks,
           max(case when pl.linktypeid = 3 then pl.relatedpostid end) as sample_duplicate_of
    from postlinks pl
    group by pl.postid
),
recent_hot_candidates as (
    select q.question_id,
           q.owneruserid,
           q.creationdate,
           q.title,
           q.primary_tag,
           q.tag_count,
           q.score,
           q.viewcount,
           q.favoritecount,
           qa.comments_on_q,
           qa.answers_count,
           qa.answers_score_sum,
           qa.max_answer_score,
           qa.upvotes_on_q,
           qa.downvotes_on_q,
           qa.favorites_on_q,
           coalesce(as2.answered_by_registered,0) as answered_by_registered,
           coalesce(as2.answered_by_unregistered,0) as answered_by_unregistered,
           coalesce(as2.distinct_answerers,0) as distinct_answerers,
           coalesce(as2.avg_answer_score,0) as avg_answer_score,
           coalesce(as2.has_accepted_answer,0) as has_accepted_answer,
           coalesce(cr.last_close_reason_id_text,'') as last_close_reason_id_text,
           cr.last_close_date,
           cr.last_reopen_date,
           coalesce(dl.duplicate_marks,0) as duplicate_marks,
           coalesce(dl.linked_marks,0) as linked_marks,
           dl.sample_duplicate_of,
           case
             when q.viewcount is null or q.viewcount = 0 then null
             else round((q.score::numeric / nullif(q.viewcount,0))::numeric, 6)
           end as score_per_view,
           case
             when qa.answers_count = 0 then null
             else round((qa.answers_score_sum::numeric / qa.answers_count)::numeric, 6)
           end as avg_answer_score_overall
    from q_with_primary_tag q
    left join q_activity qa on qa.question_id = q.question_id
    left join answerer_stats as2 on as2.question_id = q.question_id
    left join close_reasons cr on cr.question_id = q.question_id
    left join dup_links dl on dl.question_id = q.question_id
    where q.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_dim as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.upvotes,
           u.downvotes,
           u.views as profile_views,
           ru.country_hint,
           ru.signup_rank,
           bs.total_badges,
           bs.gold_badges,
           bs.silver_badges,
           bs.bronze_badges,
           bs.tag_badges,
           bs.first_badge_date,
           bs.last_badge_date
    from users u
    left join recent_users ru on ru.user_id = u.id
    left join user_badge_stats bs on bs.userid = u.id
),
question_user_bridge as (
    select rhc.question_id,
           rhc.owneruserid as user_id,
           row_number() over (partition by rhc.owneruserid order by rhc.creationdate desc, rhc.score desc) as rn_user_recent_q
    from recent_hot_candidates rhc
),
ranked_questions as (
    select rhc.*,
           ud.displayname as owner_name,
           ud.reputation as owner_reputation,
           ud.total_badges,
           ud.gold_badges,
           ud.silver_badges,
           ud.bronze_badges,
           ud.tag_badges,
           ud.country_hint,
           ud.signup_rank,
           qb.rn_user_recent_q,
           row_number() over (order by
               coalesce(rhc.score,0) * 2
               + coalesce(rhc.upvotes_on_q,0) * 1.5
               - coalesce(rhc.downvotes_on_q,0) * 1.0
               + coalesce(rhc.favorites_on_q,0) * 1.25
               + coalesce(rhc.answers_count,0) * 0.75
               + coalesce(rhc.max_answer_score,0) * 0.5
               + least(coalesce(rhc.viewcount,0)::numeric, 5000)::numeric / 5000.0
               - case when rhc.duplicate_marks > 0 then 2 else 0 end
               - case when rhc.last_close_date is not null and (rhc.last_reopen_date is null or rhc.last_reopen_date < rhc.last_close_date) then 5 else 0 end
               desc,
               rhc.creationdate desc,
               rhc.question_id desc
           ) as global_rank,
           dense_rank() over (partition by coalesce(rhc.primary_tag,'(none)') order by rhc.creationdate desc, rhc.score desc) as tag_recency_rank,
           percentile_cont(0.5) within group (order by coalesce(rhc.score,0)) over () as score_median_all,
           avg(coalesce(rhc.score,0)) over (partition by coalesce(rhc.primary_tag,'(none)')) as tag_avg_score
    from recent_hot_candidates rhc
    left join user_dim ud on ud.user_id = rhc.owneruserid
    left join question_user_bridge qb on qb.question_id = rhc.question_id and qb.user_id = rhc.owneruserid
),
normalized as (
    select rq.*,
           case
             when score_median_all is null or score_median_all = 0 then null
             else round((coalesce(rq.score,0)::numeric / nullif(score_median_all,0))::numeric, 4)
           end as score_vs_median,
           case
             when rq.tag_avg_score is null or rq.tag_avg_score = 0 then null
             else round((coalesce(rq.score,0)::numeric / nullif(rq.tag_avg_score,0))::numeric, 4)
           end as score_vs_tag_avg
    from ranked_questions rq
),
tag_popularity as (
    select t.tagname,
           t.count as tag_total_count,
           coalesce(sum(case when q.primary_tag = t.tagname then 1 else 0 end),0) as q_in_last_year
    from tags t
    left join q_with_primary_tag q on q.primary_tag = t.tagname
    group by t.tagname, t.count
),
final_scored as (
    select n.*,
           tp.tag_total_count,
           tp.q_in_last_year,
           case
             when tp.tag_total_count is null or tp.tag_total_count = 0 then 0.0
             else round(least(1.0, (coalesce(tp.q_in_last_year,0)::numeric / tp.tag_total_count::numeric)), 6)
           end as tag_recent_ratio,
           case
             when n.country_hint ilike '%united states%' or n.country_hint ilike '%usa%' then 'NA'
             when n.country_hint ilike '%india%' then 'AS'
             when n.country_hint ilike '%germany%' then 'EU'
             when n.country_hint ilike '%uk%' or n.country_hint ilike '%united kingdom%' or n.country_hint ilike '%england%' then 'EU'
             when n.country_hint ilike '%australia%' then 'OC'
             when n.country_hint ilike '%canada%' then 'NA'
             when n.country_hint = 'Unknown' then 'UN'
             else 'OT'
           end as region_hint,
           case
             when n.last_close_reason_id_text ~ '^(101|Duplicate)' then 'Duplicate'
             when n.last_close_reason_id_text ~ '^(102|Off-topic)' then 'Off-topic'
             when n.last_close_reason_id_text ~ '^(103|Needs details|Needs clarity)' then 'Needs details/clarity'
             when n.last_close_reason_id_text ~ '^(104|Needs more focus)' then 'Needs more focus'
             when n.last_close_reason_id_text ~ '^(105|Opinion)' then 'Opinion-based'
             when n.last_close_reason_id_text is null or trim(n.last_close_reason_id_text) = '' then 'None'
             else 'Other'
           end as last_close_reason_bucket
    from normalized n
    left join tag_popularity tp on tp.tagname = n.primary_tag
),
thresholds as (
    select
      percentile_cont(0.9) within group (order by coalesce(score,0)) as p90_score,
      percentile_cont(0.9) within group (order by coalesce(viewcount,0)) as p90_views,
      percentile_cont(0.9) within group (order by coalesce(favoritecount,0)) as p90_favs
    from final_scored
),
flagged as (
    select fs.*,
           case when fs.score >= th.p90_score then 1 else 0 end as is_top10_score,
           case when fs.viewcount >= th.p90_views then 1 else 0 end as is_top10_views,
           case when fs.favoritecount >= th.p90_favs then 1 else 0 end as is_top10_favs
    from final_scored fs
    cross join thresholds th
),
unioned as (
    select
        'TOP' as bucket,
        question_id,
        owneruserid,
        owner_name,
        primary_tag,
        tag_count,
        score,
        viewcount,
        favoritecount,
        upvotes_on_q,
        downvotes_on_q,
        answers_count,
        max_answer_score,
        has_accepted_answer,
        duplicate_marks,
        last_close_reason_bucket,
        global_rank,
        score_vs_median,
        score_vs_tag_avg,
        tag_recent_ratio,
        region_hint,
        rn_user_recent_q
    from flagged
    where is_top10_score = 1 or is_top10_views = 1 or is_top10_favs = 1
    union all
    select
        'RECENT' as bucket,
        question_id,
        owneruserid,
        owner_name,
        primary_tag,
        tag_count,
        score,
        viewcount,
        favoritecount,
        upvotes_on_q,
        downvotes_on_q,
        answers_count,
        max_answer_score,
        has_accepted_answer,
        duplicate_marks,
        last_close_reason_bucket,
        global_rank,
        score_vs_median,
        score_vs_tag_avg,
        tag_recent_ratio,
        region_hint,
        rn_user_recent_q
    from flagged
    where tag_recency_rank <= 5
),
dedup as (
    select u.*,
           row_number() over (partition by question_id order by case when bucket = 'TOP' then 1 else 2 end, global_rank) as keep_one
    from unioned u
),
final as (
    select d.bucket,
           d.question_id,
           d.owneruserid,
           d.owner_name,
           coalesce(d.primary_tag,'(none)') as primary_tag,
           d.tag_count,
           d.score,
           d.viewcount,
           d.favoritecount,
           d.upvotes_on_q,
           d.downvotes_on_q,
           d.answers_count,
           d.max_answer_score,
           d.has_accepted_answer,
           d.duplicate_marks,
           d.last_close_reason_bucket,
           d.global_rank,
           d.score_vs_median,
           d.score_vs_tag_avg,
           d.tag_recent_ratio,
           d.region_hint,
           d.rn_user_recent_q,
           case
             when d.owneruserid is null then 'Anonymous'
             when d.owner_name is null or d.owner_name = '' then '(no name)'
             else d.owner_name
           end as display_owner_name
    from dedup d
    where d.keep_one = 1
)
select f.*
from final f
where (f.region_hint <> 'UN' or f.score >= 5 or f.answers_count >= 2)
  and (f.duplicate_marks = 0 or f.has_accepted_answer = 1)
  and (coalesce(f.score_vs_median, 0) >= 0.8 or coalesce(f.score_vs_tag_avg, 0) >= 0.8)
order by f.bucket, f.global_rank, f.question_id;