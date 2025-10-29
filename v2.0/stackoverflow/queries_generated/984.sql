-- {"query": "984.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3848} 
with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
    coalesce(nullif(trim(u.profileimageurl), ''), 'n/a') as avatar_norm,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_desc
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_badge_stats as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
questions as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.closeddate,
    p.acceptedanswerid,
    p.lastactivitydate
  from posts p
  where p.posttypeid = 1
),
answers as (
  select
    a.id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.score,
    a.creationdate
  from posts a
  where a.posttypeid = 2
),
user_post_agg as (
  select
    q.owneruserid as user_id,
    count(*) filter (where q.closeddate is null) as open_questions,
    count(*) filter (where q.closeddate is not null) as closed_questions,
    count(*) as total_questions,
    sum(coalesce(q.viewcount,0)) as sum_views,
    sum(coalesce(q.score,0)) as sum_q_score,
    avg(nullif(q.score,0)) filter (where q.score is not null) as avg_q_score_nonzero,
    max(q.creationdate) as last_q_date,
    count(distinct a.id) as answers_received,
    sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
    sum(case when a.score < 0 then 1 else 0 end) as answers_negative
  from questions q
  left join answers a on a.question_id = q.id
  group by q.owneruserid
),
user_comment_agg as (
  select
    coalesce(c.userid, p.owneruserid, -1) as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score,0)) as comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  left join posts p on p.id = c.postid
  group by coalesce(c.userid, p.owneruserid, -1)
),
user_vote_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    sum(coalesce(v.bountyamount,0)) as bounty_total,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
dupe_close_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_date,
    count(*) as close_event_count,
    sum(case when ph.posthistorytypeid = 10 and ph.comment in ('1','101') then 1 else 0 end) as duplicate_flags
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
link_graph as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    count(*) filter (where pl.linktypeid = 3) as duplicate_count,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_duplicate_targets
  from postlinks pl
  group by pl.postid
),
tag_expansion as (
  select
    q.id as question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from questions q
  where q.tags is not null and q.tags like '<%>'
),
user_tag_focus as (
  select
    q.owneruserid as user_id,
    t.tagname,
    count(*) as tag_q_count,
    sum(q.viewcount) as tag_q_views,
    sum(q.score) as tag_q_score,
    rank() over (partition by q.owneruserid order by count(*) desc, sum(q.score) desc, tagname) as tag_rank
  from questions q
  join tag_expansion t on t.question_id = q.id
  group by q.owneruserid, t.tagname
),
accepted_answer_latency as (
  select
    q.owneruserid as asker_id,
    q.id as question_id,
    q.creationdate as question_date,
    a.id as accepted_answer_id,
    a.creationdate as accepted_date,
    extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
  from questions q
  join posts a on a.id = q.acceptedanswerid
),
user_accept_stats as (
  select
    asker_id as user_id,
    count(*) as accepted_count,
    avg(hours_to_accept) as avg_hours_to_accept,
    percentile_cont(0.5) within group (order by hours_to_accept) as p50_hours_to_accept
  from accepted_answer_latency
  group by asker_id
),
activity_calendar as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as month,
    count(*) as posts_in_month,
    sum(case when p.posttypeid = 1 then 1 else 0 end) as q_in_month,
    sum(case when p.posttypeid = 2 then 1 else 0 end) as a_in_month
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
user_streaks as (
  select
    user_id,
    count(*) as active_months,
    max(month) as last_active_month,
    sum(posts_in_month) as posts_total_in_active_months
  from activity_calendar
  group by user_id
),
-- simulate workload-heavy string ops and null logic
user_string_metrics as (
  select
    u.id as user_id,
    length(coalesce(u.displayname,'')) as len_displayname,
    length(coalesce(u.location,'')) as len_location,
    case
      when u.displayname ~* '^[a-z0-9 _.-]+$' then 1
      else 0
    end as is_simple_name,
    md5(coalesce(lower(trim(u.displayname)) || '|' || coalesce(lower(nullif(u.location,'')),'unknown'), 'anon')) as name_loc_hash
  from users u
),
-- aggregate post votes received per user via posts
post_vote_received as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received,
    sum(coalesce(v.bountyamount,0)) as bounties_received
  from posts p
  left join votes v on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
-- per-user windowed z-scores for monthly activity vs peer group
user_activity_windows as (
  select
    ac.user_id,
    ac.month,
    ac.posts_in_month,
    avg(ac.posts_in_month) over (partition by ac.month) as month_avg_all,
    stddev_pop(ac.posts_in_month) over (partition by ac.month) as month_std_all,
    case
      when stddev_pop(ac.posts_in_month) over (partition by ac.month) > 0
      then (ac.posts_in_month - avg(ac.posts_in_month) over (partition by ac.month))
           / nullif(stddev_pop(ac.posts_in_month) over (partition by ac.month), 0)
      else null
    end as month_z_all
  from activity_calendar ac
),
user_activity_peaks as (
  select distinct on (user_id)
    user_id,
    month as peak_month,
    posts_in_month as peak_posts,
    month_z_all as peak_zscore
  from user_activity_windows
  order by user_id, posts_in_month desc nulls last, month asc
),
-- combine all per-user metrics
combined as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    r.creationdate,
    r.location,
    r.websiteurl_norm,
    r.avatar_norm,
    coalesce(ub.total_badges,0) as total_badges,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    ub.first_badge_date,
    ub.last_badge_date,
    coalesce(upa.open_questions,0) as open_questions,
    coalesce(upa.closed_questions,0) as closed_questions,
    coalesce(upa.total_questions,0) as total_questions,
    coalesce(upa.sum_views,0) as sum_views,
    coalesce(upa.sum_q_score,0) as sum_q_score,
    upa.avg_q_score_nonzero,
    upa.last_q_date,
    coalesce(upa.answers_received,0) as answers_received,
    coalesce(upa.answers_positive,0) as answers_positive,
    coalesce(upa.answers_negative,0) as answers_negative,
    coalesce(uca.comment_count,0) as comment_count,
    coalesce(uca.comment_score,0) as comment_score,
    uca.last_comment_date,
    coalesce(uva.upvotes_cast,0) as upvotes_cast,
    coalesce(uva.downvotes_cast,0) as downvotes_cast,
    coalesce(uva.favorites_cast,0) as favorites_cast,
    coalesce(uva.bounty_total,0) as bounties_started,
    uva.last_vote_date,
    coalesce(pvr.upvotes_received,0) as upvotes_received,
    coalesce(pvr.downvotes_received,0) as downvotes_received,
    coalesce(pvr.bounties_received,0) as bounties_received,
    coalesce(uas.accepted_count,0) as accepted_count,
    uas.avg_hours_to_accept,
    uas.p50_hours_to_accept,
    coalesce(us.active_months,0) as active_months,
    us.last_active_month,
    coalesce(us.posts_total_in_active_months,0) as posts_total_in_active_months,
    us2.peak_month,
    us2.peak_posts,
    us2.peak_zscore,
    usm.len_displayname,
    usm.len_location,
    usm.is_simple_name,
    usm.name_loc_hash,
    -- top tag info via correlated subquery
    (
      select ut.tagname
      from user_tag_focus ut
      where ut.user_id = r.user_id and ut.tag_rank = 1
      order by ut.tagname
      limit 1
    ) as top_tag,
    (
      select ut.tag_q_count
      from user_tag_focus ut
      where ut.user_id = r.user_id and ut.tag_rank = 1
      order by ut.tagname
      limit 1
    ) as top_tag_q_count,
    -- duplicate and link stats on user's questions
    (
      select sum(coalesce(lg.duplicate_count,0))
      from questions q
      left join link_graph lg on lg.postid = q.id
      where q.owneruserid = r.user_id
    ) as user_duplicate_links,
    (
      select sum(coalesce(lg.linked_count,0))
      from questions q
      left join link_graph lg on lg.postid = q.id
      where q.owneruserid = r.user_id
    ) as user_linked_links,
    (
      select sum(case when dce.duplicate_flags > 0 then 1 else 0 end)
      from questions q
      left join dupe_close_events dce on dce.postid = q.id
      where q.owneruserid = r.user_id
    ) as questions_flagged_duplicate,
    -- string heavy: first and last word of title of latest question
    (
      select
        split_part(regexp_replace(coalesce(q.title,''), '\s+', ' ', 'g'), ' ', 1)
      from questions q
      where q.owneruserid = r.user_id
      order by q.creationdate desc nulls last
      limit 1
    ) as latest_q_first_word,
    (
      select
        regexp_replace(split_part(regexp_replace(coalesce(q.title,''), '\s+', ' ', 'g'), ' ', -1), '[^\w]+', '', 'g')
      from questions q
      where q.owneruserid = r.user_id
      order by q.creationdate desc nulls last
      limit 1
    ) as latest_q_last_word_clean
  from recent_users r
  left join user_badge_stats ub on ub.userid = r.user_id
  left join user_post_agg upa on upa.user_id = r.user_id
  left join user_comment_agg uca on uca.user_id = r.user_id
  left join user_vote_agg uva on uva.user_id = r.user_id
  left join user_accept_stats uas on uas.user_id = r.user_id
  left join user_streaks us on us.user_id = r.user_id
  left join user_activity_peaks us2 on us2.user_id = r.user_id
  left join user_string_metrics usm on usm.user_id = r.user_id
  left join post_vote_received pvr on pvr.user_id = r.user_id
),
ranked as (
  select
    c.*,
    -- composite performance-heavy ranking across several metrics
    (coalesce(c.reputation,0) / nullif(date_part('day', now() - c.creationdate),0))
      + coalesce(c.sum_q_score,0) * 0.5
      + coalesce(c.upvotes_received,0) * 0.25
      - coalesce(c.downvotes_received,0) * 0.5
      + coalesce(c.total_badges,0) * 0.1
      + coalesce(c.active_months,0) * 0.2
      + coalesce(c.bounties_received,0) * 0.05
      - coalesce(c.questions_flagged_duplicate,0) * 0.3
      as performance_score,
    dense_rank() over (
      order by
        coalesce(c.sum_q_score,0) desc,
        coalesce(c.upvotes_received,0) desc,
        coalesce(c.total_badges,0) desc,
        c.user_id asc
    ) as dense_rank_quality,
    row_number() over (
      order by
        coalesce(c.reputation,0) desc,
        coalesce(c.sum_views,0) desc,
        c.user_id
    ) as rn_global
  from combined c
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.location,
  r.websiteurl_norm,
  r.avatar_norm,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.open_questions,
  r.closed_questions,
  r.total_questions,
  r.sum_views,
  r.sum_q_score,
  r.avg_q_score_nonzero,
  r.answers_received,
  r.answers_positive,
  r.answers_negative,
  r.comment_count,
  r.comment_score,
  r.upvotes_cast,
  r.downvotes_cast,
  r.favorites_cast,
  r.upvotes_received,
  r.downvotes_received,
  r.bounties_started,
  r.bounties_received,
  r.accepted_count,
  r.avg_hours_to_accept,
  r.p50_hours_to_accept,
  r.active_months,
  r.posts_total_in_active_months,
  r.peak_month,
  r.peak_posts,
  r.peak_zscore,
  r.top_tag,
  r.top_tag_q_count,
  r.user_duplicate_links,
  r.user_linked_links,
  r.questions_flagged_duplicate,
  r.latest_q_first_word,
  r.latest_q_last_word_clean,
  r.len_displayname,
  r.len_location,
  r.is_simple_name,
  r.name_loc_hash,
  r.performance_score,
  r.dense_rank_quality,
  r.rn_global
from ranked r
where (
    r.top_tag is not null
    or (r.total_questions > 0 and r.sum_q_score is not null)
    or r.performance_score > 0
  )
  and coalesce(r.reputation,0) >= 1
  and (
    r.closed_questions = 0
    or r.open_questions > r.closed_questions
    or r.questions_flagged_duplicate is null
  )
  and (
    r.upvotes_cast >= r.downvotes_cast
    or r.downvotes_cast is null
  )
order by
  r.performance_score desc nulls last,
  r.dense_rank_quality asc,
  r.rn_global asc
limit 250;