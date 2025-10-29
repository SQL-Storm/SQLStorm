-- {"query": "745.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2783} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
           date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= now() - interval '5 years'
),
user_badge_rollup as (
    select b.userid,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
user_post_stats as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(coalesce(p.score,0)) as total_post_score,
           avg(nullif(p.viewcount,0)) as avg_viewcount_nonzero,
           max(p.creationdate) as last_post_date,
           count(*) filter (where p.closeddate is not null) as closed_count
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
answer_accepts as (
    select a.owneruserid as user_id,
           count(*) as accepts_won
    from posts q
    join posts a
      on a.parentid = q.id
     and a.id = q.acceptedanswerid
    where q.posttypeid = 1 and a.posttypeid = 2 and a.owneruserid is not null
    group by a.owneruserid
),
vote_rollup as (
    select v.userid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           count(*) filter (where v.votetypeid = 5) as favorites_cast,
           min(v.creationdate) as first_vote_date,
           max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
comment_activity as (
    select c.userid as user_id,
           count(*) as comment_count,
           avg(coalesce(c.score,0)) as avg_comment_score,
           max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
tag_expertise as (
    select p.owneruserid as user_id,
           unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname,
           count(*) as posts_with_tag,
           avg(coalesce(p.score,0)) as avg_score_with_tag
    from posts p
    where p.posttypeid in (1,2) and p.owneruserid is not null and p.tags is not null and p.tags like '<%>'
    group by p.owneruserid, unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'))
),
top_tag_per_user as (
    select t.user_id,
           t.tagname,
           t.posts_with_tag,
           t.avg_score_with_tag,
           row_number() over (partition by t.user_id order by t.posts_with_tag desc, t.avg_score_with_tag desc, t.tagname) as rn
    from tag_expertise t
),
post_link_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where l.linktypeid = 3 and l.postid = p.id) as duplicates_declared,
           count(*) filter (where l.linktypeid = 3 and l.relatedpostid = p.id) as duplicates_of_others,
           count(*) filter (where l.linktypeid = 1 and l.postid = p.id) as links_out,
           count(*) filter (where l.linktypeid = 1 and l.relatedpostid = p.id) as links_in
    from posts p
    left join postlinks l
      on l.postid = p.id or l.relatedpostid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
edits_and_closures as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_date,
           count(*) filter (where ph.posthistorytypeid in (10,11)) as close_reopen_events,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_close_date,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
    from posthistory ph
    group by ph.postid
),
user_edit_stats as (
    select p.owneruserid as user_id,
           sum(coalesce(e.edit_events,0)) as total_edit_events,
           max(e.last_edit_date) as last_edit_date,
           sum(coalesce(e.close_reopen_events,0)) as total_close_reopen_events,
           max(e.last_close_date) as last_close_date
    from posts p
    left join edits_and_closures e on e.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
question_answer_latency as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           min(a.creationdate) as first_answer_time,
           q.creationdate as question_time,
           extract(epoch from (min(a.creationdate) - q.creationdate)) as secs_to_first_answer
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate
),
asker_latency_rollup as (
    select asker_id as user_id,
           avg(secs_to_first_answer) filter (where secs_to_first_answer is not null) as avg_secs_to_first_answer
    from question_answer_latency
    group by asker_id
),
user_activity_rank as (
    select ru.user_id,
           dense_rank() over (order by coalesce(ups.a_count,0) + coalesce(ups.q_count,0) desc, coalesce(vr.upvotes_cast,0) desc, coalesce(ru.reputation,0) desc) as activity_rank
    from recent_users ru
    left join user_post_stats ups on ups.user_id = ru.user_id
    left join vote_rollup vr on vr.user_id = ru.user_id
),
null_safety as (
    select ru.user_id,
           case when ru.displayname is null or ru.displayname ~ '^\s*$' then '(anonymous)' else ru.displayname end as safe_displayname,
           coalesce(ru.location, 'Unknown') as safe_location
    from recent_users ru
),
cross_user_comp as (
    select ru.user_id,
           sum(case when ru.reputation > ru2.reputation then 1 else 0 end) as users_with_lower_rep_last5y
    from recent_users ru
    cross join recent_users ru2
    group by ru.user_id
)
select
    ru.user_id,
    ns.safe_displayname as displayname,
    ns.safe_location as location,
    ru.websiteurl_norm as website,
    ru.reputation,
    ru.cohort_month,
    coalesce(ubr.badge_count,0) as badge_count,
    coalesce(ubr.gold_count,0) as gold_badges,
    coalesce(ubr.silver_count,0) as silver_badges,
    coalesce(ubr.bronze_count,0) as bronze_badges,
    coalesce(ups.q_count,0) as questions_posted,
    coalesce(ups.a_count,0) as answers_posted,
    coalesce(ans.accepts_won,0) as accepts_won,
    round(coalesce(ans.accepts_won::numeric,0) / nullif(ups.a_count,0), 4) as accept_rate,
    coalesce(ups.total_post_score,0) as total_post_score,
    coalesce(ups.avg_viewcount_nonzero,0)::numeric(18,2) as avg_viewcount_nonzero,
    ups.last_post_date,
    coalesce(ups.closed_count,0) as questions_closed,
    coalesce(vr.upvotes_cast,0) as upvotes_cast,
    coalesce(vr.downvotes_cast,0) as downvotes_cast,
    coalesce(vr.favorites_cast,0) as favorites_cast,
    vr.first_vote_date,
    vr.last_vote_date,
    coalesce(ca.comment_count,0) as comments_made,
    ca.avg_comment_score,
    ca.last_comment_date,
    tt.tagname as top_tag,
    tt.posts_with_tag as top_tag_posts,
    tt.avg_score_with_tag as top_tag_avg_score,
    coalesce(pla.duplicates_declared,0) as dup_links_out,
    coalesce(pla.duplicates_of_others,0) as dup_links_in,
    coalesce(pla.links_out,0) as links_out,
    coalesce(pla.links_in,0) as links_in,
    coalesce(ues.total_edit_events,0) as total_edit_events,
    ues.last_edit_date,
    coalesce(ues.total_close_reopen_events,0) as total_close_reopen_events,
    ues.last_close_date,
    alr.avg_secs_to_first_answer,
    uar.activity_rank,
    cuc.users_with_lower_rep_last5y,
    case
      when coalesce(vr.upvotes_cast,0) - coalesce(vr.downvotes_cast,0) >= 100 then 'Highly Positive'
      when coalesce(vr.upvotes_cast,0) - coalesce(vr.downvotes_cast,0) between 0 and 99 then 'Balanced'
      else 'Critical'
    end as voting_profile,
    case
      when ru.reputation >= 100000 then 'Legend'
      when ru.reputation >= 50000 then 'Elite'
      when ru.reputation >= 10000 then 'Veteran'
      when ru.reputation >= 1000 then 'Established'
      else 'Rising'
    end as reputation_band
from recent_users ru
left join null_safety ns on ns.user_id = ru.user_id
left join user_badge_rollup ubr on ubr.userid = ru.user_id
left join user_post_stats ups on ups.user_id = ru.user_id
left join answer_accepts ans on ans.user_id = ru.user_id
left join vote_rollup vr on vr.user_id = ru.user_id
left join comment_activity ca on ca.user_id = ru.user_id
left join top_tag_per_user tt on tt.user_id = ru.user_id and tt.rn = 1
left join post_link_activity pla on pla.user_id = ru.user_id
left join user_edit_stats ues on ues.user_id = ru.user_id
left join asker_latency_rollup alr on alr.user_id = ru.user_id
left join user_activity_rank uar on uar.user_id = ru.user_id
left join cross_user_comp cuc on cuc.user_id = ru.user_id
where
    -- complicated predicate mixing strings, NULLs, arrays, time and math
    (
      ru.reputation >= 1000
      or (coalesce(ups.a_count,0) + coalesce(ups.q_count,0)) >= 50
      or coalesce(ubr.gold_count,0) >= 1
    )
    and (ru.location is null or ru.location !~* '(remote|planet earth)')
    and (coalesce(tt.tagname,'') = '' or length(tt.tagname) between 2 and 35)
    and (
      coalesce(ues.last_edit_date, ru.creationdate) >= ru.creationdate
      and coalesce(ups.last_post_date, ru.creationdate) >= ru.creationdate
    )
    and (
      -- keep users with good activity or intriguing imbalance
      coalesce(vr.upvotes_cast,0) >= greatest(10, coalesce(vr.downvotes_cast,0) - 5)
      or (coalesce(vr.downvotes_cast,0) >= 25 and coalesce(vr.upvotes_cast,0) = 0)
    )
order by
    uar.activity_rank nulls last,
    ru.reputation desc,
    coalesce(ups.a_count,0) + coalesce(ups.q_count,0) desc,
    ru.user_id
limit 500;