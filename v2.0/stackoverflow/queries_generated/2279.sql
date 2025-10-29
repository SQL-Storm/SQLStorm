-- {"query": "2279.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1333} 
with RecursiveRelatedPosts as (
    select p.Id, p.Title, p.PostTypeId, pl.RelatedPostId, 1 as Depth
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 1
    where p.PostTypeId = 1
    union all
    select r.Id, r.Title, r.PostTypeId, pl.RelatedPostId, r.Depth + 1
    from RecursiveRelatedPosts r
    join PostLinks pl on pl.PostId = r.RelatedPostId and pl.LinkTypeId = 1
    where r.Depth < 3
),
UserBadgeAgg as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end), 0) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreRank as (
    select
        p.Id,
        p.PostTypeId,
        p.Score,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.CreationDate asc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
),
PostCommentsAgg as (
    select 
        c.PostId,
        count(*) as CommentCount,
        count(case when c.UserId is null then 1 end) as AnonymousComments,
        max(c.Score) as MaxCommentScore,
        string_agg(distinct coalesce(nullif(c.UserDisplayName, ''), 'Anonymous'), ', ' order by c.UserDisplayName) as CommentAuthors
    from Comments c
    group by c.PostId
),
QuestionsDetailed as (
    select 
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.Tags,
        q.CreationDate,
        ur.DisplayName,
        ur.Reputation,
        pb.GoldBadges,
        pb.SilverBadges,
        pb.BronzeBadges,
        pb.TagBasedBadges,
        pc.CommentCount,
        pc.AnonymousComments,
        pc.MaxCommentScore,
        pc.CommentAuthors,
        pr.Depth as RelatedDepth,
        pr.RelatedPostId
    from Posts q
    left join Users ur on ur.Id = q.OwnerUserId
    left join UserBadgeAgg pb on pb.UserId = q.OwnerUserId
    left join PostCommentsAgg pc on pc.PostId = q.Id
    left join RecursiveRelatedPosts pr on pr.Id = q.Id
    where q.PostTypeId = 1
),
AnswerStats as (
    select 
        a.ParentId as QuestionId,
        count(*) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate,
        min(a.CreationDate) as FirstAnswerDate,
        count(distinct a.OwnerUserId) as UniqueAnswerers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
ClosedQuestionDetails as (
    select 
        ph.PostId,
        min(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId,
        count(case when ph.PostHistoryTypeId = 10 then 1 else null end) as CloseVoteCount,
        max(ph.CreationDate) as LastCloseVoteDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
)
select
    qd.Id as QuestionId,
    qd.Title,
    qd.DisplayName as QuestionOwner,
    qd.Reputation as OwnerReputation,
    qd.GoldBadges, qd.SilverBadges, qd.BronzeBadges, qd.TagBasedBadges,
    qd.Score as QuestionScore,
    qd.ViewCount,
    qd.AnswerCount as CachedAnswerCount,
    asg.TotalAnswers,
    asg.AvgAnswerScore,
    asg.LastAnswerDate,
    asg.FirstAnswerDate,
    asg.UniqueAnswerers,
    qd.CommentCount,
    qd.AnonymousComments,
    qd.MaxCommentScore,
    qd.CommentAuthors,
    cq.CloseReasonId,
    cq.CloseVoteCount,
    cq.LastCloseVoteDate,
    qd.RelatedDepth,
    qd.RelatedPostId,
    -- Window function calculating running sum of scores over questions ordered by creation date
    sum(qd.Score) over (order by qd.CreationDate rows between unbounded preceding and current row) as RunningQuestionScore,
    -- Complex predicate: check if question is "hot" (e.g., score > average + stddev)
    case 
        when qd.Score > (
            select avg(Score) + stddev_pop(Score) 
            from Posts p 
            where p.PostTypeId = 1
        ) then 'Hot' 
        else 'Normal' 
    end as Hotness,
    -- String expression: concatenated tag list length
    length(coalesce(qd.Tags, '')) as TagStringLength,
    -- Boolean expression on NULLs: is the question closed recently (within last 30 days from last activity)
    case 
        when cq.CloseVoteCount > 0 and qd.RelatedDepth is not null and qd.CreationDate > current_timestamp - interval '30 days' then true
        else false
    end as RecentlyClosedAndLinkedFlag
from QuestionsDetailed qd
left join AnswerStats asg on asg.QuestionId = qd.Id
left join ClosedQuestionDetails cq on cq.PostId = qd.Id
where qd.Score > 0
order by RunningQuestionScore desc, qd.ViewCount desc
limit 100;