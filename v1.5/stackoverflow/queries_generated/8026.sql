-- {"query": "8026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2483} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as country_guess,
           dense_rank() over (order by u.creationdate desc) as signup_rank
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select p.id as post_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.closeddate,
           p.favoritecount
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.id as answer_id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
),
user_badges as (
    select b.userid as user_id,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           count(*) as total_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q_engagement as (
    select q.post_id,
           count(distinct c.id) as comment_count,
           count(*) filter (where v.votetypeid = 2) as upvotes,
           count(*) filter (where v.votetypeid = 3) as downvotes,
           count(*) filter (where v.votetypeid = 5) as favorites,
           count(distinct pl.relatedpostid) filter (where pl.linktypeid = 1) as linked_to_count,
           count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as duplicate_of_count
    from question_posts q
    left join comments c on c.postid = q.post_id
    left join votes v on v.postid = q.post_id
    left join postlinks pl on pl.postid = q.post_id
    group by q.post_id
),
answer_stats as (
    select a.question_id,
           count(*) as answers_total,
           count(*) filter (where a.score > 0) as answers_positive,
           avg(a.score::numeric) as avg_answer_score,
           max(a.score) as max_answer_score,
           min(a.score) as min_answer_score,
           min(a.creationdate) as first_answer_date,
           max(a.creationdate) as last_answer_date
    from answer_posts a
    group by a.question_id
),
accepted_answer_lag as (
    select q.id as question_id,
           q.creationdate as question_created,
           acc.id as accepted_answer_id,
           acc.creationdate as accepted_created,
           extract(epoch from (acc.creationdate - q.creationdate))/3600.0 as hours_to_accept
    from posts q
    join posts acc on acc.id = q.acceptedanswerid
    where q.posttypeid = 1
),
hotness_calc as (
    select q.post_id,
           q.score,
           q.viewcount,
           q.creationdate,
           coalesce(e.upvotes,0) as upvotes,
           coalesce(e.downvotes,0) as downvotes,
           coalesce(e.comment_count,0) as comment_count,
           coalesce(e.favorites,0) as favorites,
           0.6*ln(1+coalesce(q.viewcount,0)) +
           3.0*coalesce(e.upvotes,0) -
           2.0*coalesce(e.downvotes,0) +
           1.0*coalesce(e.comment_count,0) +
           1.5*coalesce(e.favorites,0) +
           0.5*coalesce(q.answercount,0) -
           extract(epoch from (now() - coalesce(q.creationdate, now())))/86400.0 as hotness_score
    from question_posts q
    left join q_engagement e on e.post_id = q.post_id
),
tag_expansion as (
    select q.post_id,
           unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tagname
    from question_posts q
),
tag_rank as (
    select t.tagname,
           count(*) as q_count,
           percent_rank() over (order by count(*) asc) as popularity_percentile
    from tag_expansion t
    group by t.tagname
),
user_activity as (
    select q.user_id,
           count(*) as questions_asked,
           avg(q.score::numeric) as avg_q_score,
           sum(coalesce(e.upvotes,0) - coalesce(e.downvotes,0)) as net_votes,
           sum(coalesce(e.comment_count,0)) as comments_received,
           max(q.creationdate) as last_question_date
    from question_posts q
    left join q_engagement e on e.post_id = q.post_id
    group by q.user_id
),
user_window as (
    select u.user_id,
           u.displayname,
           u.reputation,
           u.country_guess,
           ua.questions_asked,
           ua.avg_q_score,
           ua.net_votes,
           row_number() over (partition by u.country_guess order by ua.net_votes desc nulls last, u.reputation desc) as rn_country_net,
           dense_rank() over (order by coalesce(ua.questions_asked,0) desc, u.reputation desc) as dense_activity_rank
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
),
question_quality as (
    select q.post_id,
           q.user_id,
           q.title,
           q.tags,
           q.creationdate,
           q.score,
           q.viewcount,
           q.answercount,
           e.upvotes, e.downvotes, e.comment_count, e.favorites,
           a.answers_total, a.avg_answer_score, a.max_answer_score,
           aal.hours_to_accept,
           h.hotness_score,
           coalesce(nullif(trim(q.title), ''), '[no title]') as normalized_title,
           case
             when q.closeddate is not null then 'closed'
             when coalesce(e.downvotes,0) > coalesce(e.upvotes,0) then 'controversial'
             when coalesce(a.answers_total,0) = 0 and now() - q.creationdate > interval '30 days' then 'unanswered'
             else 'active'
           end as status_bucket
    from question_posts q
    left join q_engagement e on e.post_id = q.post_id
    left join answer_stats a on a.question_id = q.post_id
    left join accepted_answer_lag aal on aal.question_id = q.post_id
    left join hotness_calc h on h.post_id = q.post_id
),
recent_edits as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_date,
           count(*) filter (where ph.posthistorytypeid in (10)) as close_votes_events
    from posthistory ph
    where ph.creationdate >= now() - interval '365 days'
    group by ph.postid
),
dup_chain as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as original_post_id,
           row_number() over (partition by pl.postid order by pl.creationdate asc) as rn
    from postlinks pl
    where pl.linktypeid = 3
),
final_set as (
    select
        qq.post_id,
        qq.user_id,
        u.displayname,
        u.reputation,
        uw.country_guess,
        uw.rn_country_net,
        uw.dense_activity_rank,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        qq.normalized_title as title,
        qq.tags,
        qq.creationdate,
        qq.status_bucket,
        qq.score,
        qq.viewcount,
        qq.answercount,
        qq.upvotes, qq.downvotes, qq.comment_count, qq.favorites,
        qq.answers_total, qq.avg_answer_score, qq.max_answer_score,
        qq.hours_to_accept,
        qq.hotness_score,
        re.edit_events, re.last_edit_date, re.close_votes_events,
        tr.tagname as top_tag,
        tr2.popularity_percentile as tag_popularity,
        dc.original_post_id as duplicate_of_id
    from question_quality qq
    left join users u on u.id = qq.user_id
    left join user_badges ub on ub.user_id = qq.user_id
    left join user_window uw on uw.user_id = qq.user_id
    left join recent_edits re on re.postid = qq.post_id
    left join lateral (
        select te.tagname
        from tag_expansion te
        where te.post_id = qq.post_id
        order by length(te.tagname) asc, te.tagname asc
        limit 1
    ) tr on true
    left join tag_rank tr2 on tr2.tagname = tr.tagname
    left join dup_chain dc on dc.dup_post_id = qq.post_id and dc.rn = 1
),
ranked as (
    select *,
           row_number() over (
              order by
                coalesce(hotness_score, -1e9) desc,
                coalesce(score, -1e9) desc,
                coalesce(viewcount, -1e9) desc
           ) as global_rank,
           ntile(20) over (order by coalesce(hotness_score, -1e9) desc) as hotness_bucket
    from final_set
)
select
    r.post_id,
    r.user_id,
    coalesce(r.displayname, '[unknown]') as displayname,
    r.reputation,
    r.country_guess,
    r.rn_country_net,
    r.dense_activity_rank,
    r.total_badges,
    r.gold_badges,
    r.title,
    r.tags,
    r.status_bucket,
    r.score,
    r.viewcount,
    r.answercount,
    r.upvotes,
    r.downvotes,
    r.comment_count,
    r.favorites,
    r.answers_total,
    round(coalesce(r.avg_answer_score,0)::numeric, 3) as avg_answer_score,
    r.max_answer_score,
    round(coalesce(r.hours_to_accept,0)::numeric, 2) as hours_to_accept,
    round(coalesce(r.hotness_score,0)::numeric, 3) as hotness_score,
    r.edit_events,
    r.last_edit_date,
    r.close_votes_events,
    r.top_tag,
    r.tag_popularity,
    r.duplicate_of_id,
    r.global_rank,
    r.hotness_bucket
from ranked r
where (r.status_bucket <> 'closed' or r.close_votes_events = 0)
  and (
    r.hotness_score is not null
    or r.answers_total is not null
    or r.edit_events is not null
  )
  and (
    r.top_tag is null
    or r.tag_popularity <= 0.95
  )
order by r.global_rank
limit 500;