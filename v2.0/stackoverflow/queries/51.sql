with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
    from users u
    where u.creationdate >= coalesce(
        (select max(p.creationdate) - interval '365 days' from posts p),
        (timestamp '2024-10-01 12:34:56') - interval '365 days'
    )
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        sum(coalesce(p.score,0)) as post_score_sum,
        max(p.lastactivitydate) as last_post_activity,
        count(distinct c.id) as comments_made
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    left join votes v on v.userid = u.user_id
    left join comments c on c.userid = u.user_id
    group by u.user_id
),
accepted_answer_stats as (
    select
        q.owneruserid as asker_id,
        count(*) as accepted_answers_received,
        sum(a.score) as accepted_answer_score_sum
    from posts q
    join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.owneruserid
),
badge_rollup as (
    select
        b.userid,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold,
        count(*) filter (where b.class = 2) as silver,
        count(*) filter (where b.class = 3) as bronze,
        count(*) filter (where b.tagbased = true) as tag_badges
    from badges b
    group by b.userid
),
tag_usage as (
    select
        p.owneruserid as user_id,
        lower(trim(t.tag_value)) as tag_name,
        count(*) as tag_q_count
    from posts p
    cross join lateral (
        select unnest(
            case
                when p.posttypeid = 1 and p.tags is not null and length(p.tags) >= 2
                then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
                else array[]::text[]  -- use text array literal for broader compatibility
            end
        ) as tag_value
    ) as t
    where p.posttypeid = 1
    group by p.owneruserid, lower(trim(t.tag_value))
),
top_tag_per_user as (
    select user_id, tag_name, tag_q_count
    from (
        select
            tu.*,
            row_number() over (partition by tu.user_id order by tu.tag_q_count desc, tu.tag_name) as rn
        from tag_usage tu
    ) s
    where rn = 1
),
question_quality as (
    select
        p.owneruserid as user_id,
        count(*) as q_count,
        avg(coalesce(p.score,0)) as avg_q_score,
        percentile_cont(0.5) within group (order by coalesce(p.viewcount,0)) as med_q_views,
        sum(case when p.closeddate is null then 0 else 1 end) as closed_q_count
    from posts p
    where p.posttypeid = 1
    group by p.owneruserid
),
answer_quality as (
    select
        p.owneruserid as user_id,
        count(*) as a_count,
        avg(coalesce(p.score,0)) as avg_a_score,
        sum(case when exists (
            select 1
            from posts q
            where q.acceptedanswerid = p.id
        ) then 1 else 0 end) as accepted_as_answer_count
    from posts p
    where p.posttypeid = 2
    group by p.owneruserid
),
linking_behavior as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        p.owneruserid as source_user,
        rp.owneruserid as target_user
    from postlinks pl
    join posts p on p.id = pl.postid
    join posts rp on rp.id = pl.relatedpostid
),
user_link_stats as (
    select
        r.user_id,
        count(*) filter (where lb.linktypeid = 1) as links_made,
        count(*) filter (where lb.linktypeid = 3) as marked_duplicate,
        count(*) filter (where lb.target_user is distinct from lb.source_user) as links_to_others
    from recent_users r
    left join linking_behavior lb on lb.source_user = r.user_id
    group by r.user_id
),
post_edits as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit
    from posthistory ph
    group by ph.postid
),
user_edit_span as (
    select
        p.owneruserid as user_id,
        count(*) as posts_with_edits,
        avg(extract(epoch from (coalesce(pe.last_edit, p.lastactivitydate) - coalesce(pe.first_edit, p.creationdate)))) as avg_edit_lifespan_seconds
    from posts p
    left join post_edits pe on pe.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
voter_mix as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_on_posts,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_on_posts
    from posts p
    left join votes v on v.postid = p.id and v.votetypeid in (2,3)
    where p.owneruserid is not null
    group by p.owneruserid
),
activity_rank as (
    select
        u.user_id,
        dense_rank() over (order by ua.total_posts desc nulls last, ua.post_score_sum desc nulls last) as post_activity_rank,
        dense_rank() over (order by coalesce(vmx.upvotes_on_posts,0) + coalesce(vmx.downvotes_on_posts,0) desc) as vote_received_rank,
        dense_rank() over (order by coalesce(qa.q_count,0) + coalesce(aa.a_count,0) desc) as qa_volume_rank
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join voter_mix vmx on vmx.user_id = u.user_id
    left join question_quality qa on qa.user_id = u.user_id
    left join answer_quality aa on aa.user_id = u.user_id
),
cohort_stats as (
    select
        cohort_month,
        count(*) as cohort_users,
        avg(reputation) as avg_rep,
        percentile_cont(0.9) within group (order by reputation) as p90_rep
    from recent_users
    group by cohort_month
),
complex_filter as (
    select
        u.user_id
    from recent_users u
    left join badge_rollup b on b.userid = u.user_id
    left join question_quality q on q.user_id = u.user_id
    left join answer_quality a on a.user_id = u.user_id
    where
        coalesce(b.gold,0) + coalesce(b.silver,0) + coalesce(b.bronze,0) >= 3
        or (coalesce(q.q_count,0) >= 5 and coalesce(a.a_count,0) >= 5)
        or (u.reputation >= coalesce((select p90_rep from cohort_stats cs where cs.cohort_month = u.cohort_month), 0))
),
null_logic_demo as (
    select
        u.user_id,
        case
            when u.websiteurl ilike '%github%' then 'github'
            when u.websiteurl ilike '%gitlab%' then 'gitlab'
            when nullif(u.websiteurl, 'n/a') is null then 'none'
            else 'other'
        end as site_bucket
    from recent_users u
),
string_play as (
    select
        u.user_id,
        trim(both from regexp_replace(coalesce(u.displayname,'[unknown]'), '\s+', ' ', 'g')) as clean_name,
        upper(substring(coalesce(u.location, 'Unknown'), 1, 20)) as loc_key,
        length(coalesce(u.displayname,'')) as name_len
    from recent_users u
),
aggregate_scores as (
    select
        u.user_id,
        (
            coalesce(ua.total_posts,0)*1.0
            + coalesce(ua.post_score_sum,0)*0.5
            + coalesce(b.badges_total,0)*2.0
            + coalesce(aa.accepted_as_answer_count,0)*3.0
            + coalesce(uas.posts_with_edits,0)*0.25
            + coalesce(uls.links_to_others,0)*0.1
            - greatest(coalesce(qq.closed_q_count,0) - 1, 0)*0.75
        ) as engagement_score
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join badge_rollup b on b.userid = u.user_id
    left join answer_quality aa on aa.user_id = u.user_id
    left join user_edit_span uas on uas.user_id = u.user_id
    left join user_link_stats uls on uls.user_id = u.user_id
    left join question_quality qq on qq.user_id = u.user_id
),
final as (
    select
        u.user_id,
        sp.clean_name as display_name_clean,
        u.reputation,
        u.cohort_month,
        cs.cohort_users,
        cs.avg_rep,
        ba.badges_total,
        ba.gold, ba.silver, ba.bronze,
        coalesce(tt.tag_name, '(none)') as top_tag,
        coalesce(tt.tag_q_count, 0) as top_tag_q_count,
        qa.q_count, qa.avg_q_score, qa.med_q_views, qa.closed_q_count,
        aa.a_count, aa.avg_a_score, aa.accepted_as_answer_count,
        ua.total_posts, ua.post_score_sum, ua.upvotes_cast, ua.downvotes_cast, ua.comments_made,
        vmx.upvotes_on_posts, vmx.downvotes_on_posts,
        ues.posts_with_edits, cast(round(ues.avg_edit_lifespan_seconds) as bigint) as avg_edit_lifespan_seconds,
        uls.links_made, uls.marked_duplicate, uls.links_to_others,
        nl.site_bucket,
        ar.post_activity_rank, ar.vote_received_rank, ar.qa_volume_rank,
        ag.engagement_score,
        case
            when cf.user_id is not null then true
            else false
        end as passes_complex_filter,
        u.websiteurl,
        sp.loc_key,
        sp.name_len,
        u.creationdate,
        ua.last_post_activity
    from recent_users u
    left join cohort_stats cs on cs.cohort_month = u.cohort_month
    left join badge_rollup ba on ba.userid = u.user_id
    left join top_tag_per_user tt on tt.user_id = u.user_id
    left join question_quality qa on qa.user_id = u.user_id
    left join answer_quality aa on aa.user_id = u.user_id
    left join user_activity ua on ua.user_id = u.user_id
    left join voter_mix vmx on vmx.user_id = u.user_id
    left join user_edit_span ues on ues.user_id = u.user_id
    left join user_link_stats uls on uls.user_id = u.user_id
    left join null_logic_demo nl on nl.user_id = u.user_id
    left join string_play sp on sp.user_id = u.user_id
    left join activity_rank ar on ar.user_id = u.user_id
    left join aggregate_scores ag on ag.user_id = u.user_id
    left join complex_filter cf on cf.user_id = u.user_id
),
ranked as (
    select
        f.user_id,
        f.display_name_clean,
        f.reputation,
        f.cohort_month,
        f.cohort_users,
        f.avg_rep,
        f.badges_total,
        f.gold,
        f.silver,
        f.bronze,
        f.top_tag,
        f.top_tag_q_count,
        f.q_count,
        f.avg_q_score,
        f.med_q_views,
        f.closed_q_count,
        f.a_count,
        f.avg_a_score,
        f.accepted_as_answer_count,
        f.total_posts,
        f.post_score_sum,
        f.upvotes_cast,
        f.downvotes_cast,
        f.comments_made,
        f.upvotes_on_posts,
        f.downvotes_on_posts,
        f.posts_with_edits,
        f.avg_edit_lifespan_seconds,
        f.links_made,
        f.marked_duplicate,
        f.links_to_others,
        f.site_bucket,
        f.post_activity_rank,
        f.vote_received_rank,
        f.qa_volume_rank,
        f.engagement_score,
        f.passes_complex_filter,
        f.websiteurl,
        f.loc_key,
        f.name_len,
        f.creationdate,
        f.last_post_activity,
        row_number() over (order by f.passes_complex_filter desc, f.engagement_score desc nulls last, f.reputation desc, f.user_id) as global_rownum,
        rank() over (partition by f.cohort_month order by f.engagement_score desc nulls last, f.reputation desc) as cohort_rank
    from final f
)
select *
from ranked
where
    global_rownum <= 500
    or cohort_rank <= 25
order by
    passes_complex_filter desc,
    engagement_score desc nulls last,
    reputation desc,
    user_id;