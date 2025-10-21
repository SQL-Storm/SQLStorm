-- {"query": "5003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1427} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from
        Posts p
    where
        p.PostTypeId = 1
        and p.CreationDate > current_date - interval '90 days'
),
question_stats as (
    select
        q.QuestionId,
        q.Title,
        u.DisplayName as OwnerName,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        count(distinct a.Id) filter (where a.CreationDate > p.CreationDate and a.Score > 0) as PositiveAnswersAfterPost,
        sum(case when c.Score >= 5 then 1 else 0 end) as HighScoreCommentCount,
        max(c.CreationDate) as LastCommentDate
    from
        recent_questions q
        inner join Posts p on p.Id = q.QuestionId
        left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
        left join Comments c on c.PostId = p.Id
        left join Users u on u.Id = p.OwnerUserId
    where
        q.rn <= 3
    group by
        q.QuestionId, q.Title, u.DisplayName, p.ViewCount, p.Score, p.AnswerCount
),
tag_info as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName
    from
        Posts p
    where
        p.PostTypeId = 1
        and p.Tags is not null
),
dominant_tags as (
    select
        t.TagName,
        count(*) as UseCount,
        rank() over (order by count(*) desc) as tag_rank
    from
        tag_info t
    group by
        t.TagName
),
badge_summary as (
    select
        u.Id as UserId,
        count(b.Id) as TotalBadges,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by
        u.Id
),
vote_agg as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as Upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as Downvotes,
        count(distinct v.UserId) as UniqueVoters
    from
        Posts p
        left join Votes v on v.PostId = p.Id
    group by
        p.Id
),
link_counts as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedPosts,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks
    from
        PostLinks pl
    group by
        pl.PostId
),
closed_reasons as (
    select
        ph.PostId,
        max(crt.Name) as CloseReason
    from
        PostHistory ph
        join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
        left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment -- CloseReasonId stored as comment string
    where
        ph.PostHistoryTypeId = 10
    group by
        ph.PostId
)
select
    qs.QuestionId,
    qs.Title,
    coalesce(qs.OwnerName, 'Anonymous') as OwnerName,
    qs.ViewCount,
    qs.Score,
    qs.AnswerCount,
    COALESCE(badges.TotalBadges, 0) as TotalBadges,
    COALESCE(badges.GoldBadges, 0) as GoldBadges,
    COALESCE(badges.SilverBadges, 0) as SilverBadges,
    COALESCE(badges.BronzeBadges, 0) as BronzeBadges,
    va.Upvotes,
    va.Downvotes,
    va.UniqueVoters,
    lc.LinkedPosts,
    lc.DuplicateLinks,
    cr.CloseReason,
    array_agg(distinct ti.TagName order by ti.TagName) as Tags,
    dt.TagName as DominantTag,
    dt.UseCount as DominantTagFrequency,
    case
        when qs.HighScoreCommentCount >= 5 then 'Heavily Discussed'
        when qs.AnswerCount >= 3 and qs.PositiveAnswersAfterPost >= 2 then 'Active & High Quality Answers'
        when cr.CloseReason is not null then concat('Closed: ', cr.CloseReason)
        else 'Normal'
    end as ActivitySummary,
    (qs.Score * COALESCE(va.Upvotes, 0))::float / greatest(qs.ViewCount, 1) as ScoreViewRatio,
    length(qs.Title) as TitleLength,
    qs.LastCommentDate
from
    question_stats qs
    left join badge_summary badges on badges.UserId = (select OwnerUserId from Posts where Id = qs.QuestionId)
    left join vote_agg va on va.PostId = qs.QuestionId
    left join link_counts lc on lc.PostId = qs.QuestionId
    left join closed_reasons cr on cr.PostId = qs.QuestionId
    left join tag_info ti on ti.PostId = qs.QuestionId
    left join lateral (
        select dt.TagName, dt.UseCount
        from dominant_tags dt
        where dt.TagName = ti.TagName
        order by dt.UseCount desc
        limit 1
    ) dt on true
group by
    qs.QuestionId,
    qs.Title,
    qs.OwnerName,
    qs.ViewCount,
    qs.Score,
    qs.AnswerCount,
    badges.TotalBadges,
    badges.GoldBadges,
    badges.SilverBadges,
    badges.BronzeBadges,
    va.Upvotes,
    va.Downvotes,
    va.UniqueVoters,
    lc.LinkedPosts,
    lc.DuplicateLinks,
    cr.CloseReason,
    qs.HighScoreCommentCount,
    qs.PositiveAnswersAfterPost,
    dt.TagName,
    dt.UseCount,
    qs.Title,
    qs.LastCommentDate
having
    qs.ViewCount > 20
order by
    ScoreViewRatio desc nulls last,
    qs.ViewCount desc
limit 50;