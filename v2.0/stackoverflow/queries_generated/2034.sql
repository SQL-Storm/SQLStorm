-- {"query": "2034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1513} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0
    union all
    select 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        p.Level + 1
    from Tags child
    join Posts p on child.ExcerptPostId = p.Id
    join RecursiveTagHierarchy rth on rth.Id = child.Id and rth.Level < 3
), 

UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by max(b.Date) desc nulls last) as LatestBadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),

PostScoreStats as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags,
        least(p.Score * 1.0 / greatest(p.ViewCount, 1), 10) as ScorePerView,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
),

AcceptedAnswerInfo as (
    select 
        q.Id as QuestionId,
        ans.Id as AcceptedAnswerId,
        ans.OwnerUserId as AcceptedAnswerOwnerId,
        ans.Score as AcceptedAnswerScore
    from Posts q
    left join Posts ans on q.AcceptedAnswerId = ans.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),

UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        sum(vb.VoteCount) as TotalVotesCast,
        min(u.CreationDate) over () as EarliestUser,
        max(u.LastAccessDate) over () as LatestAccessDate,
        max(vb.LastVoteDate) as LastVoteDate,
        row_number() over (order by u.Reputation desc) as UserRankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select 
            v.UserId,
            count(v.Id) as VoteCount,
            max(v.CreationDate) as LastVoteDate
        from Votes v
        group by v.UserId
    ) vb on vb.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),

ComplexPostAnalysis as (
    select 
        ps.Id as PostId,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.CreationDate,
        ps.Score,
        ps.Tags,
        -- Extract first tag or NULL
        split_part(regexp_replace(ps.Tags, '[<>]', ' ', 'g'), ' ', 1) as FirstTag,
        -- Length of body in chars
        length(p.Body) as BodyLength,
        -- Calculation including null-safe avg comment length for post
        coalesce((
            select avg(length(c.Text))
            from Comments c
            where c.PostId = ps.Id
        ), 0) as AvgCommentLength,
        -- Window function: cumulative count posts per user ordered by creation date
        count(*) over(partition by ps.OwnerUserId order by ps.CreationDate rows between unbounded preceding and current row) as PostsTillNow,
        -- Null logic: Flag posts with no owner or with low score and no accepted answer
        case 
            when ps.OwnerUserId is null or ps.OwnerUserId = -1 then 'Orphan'
            when ps.Score < 0 and not exists (
                select 1 from AcceptedAnswerInfo aai where aai.QuestionId = ps.Id
            ) then 'LowScoreNoAccepted'
            else 'Normal'
        end as PostQualityFlag
    from Posts ps
    left join Posts p on p.Id = ps.Id
),

FinalSelectedPosts as (
    select 
        cp.PostId,
        cp.PostTypeId,
        u.DisplayName as OwnerName,
        cp.CreationDate,
        cp.Score,
        cp.FirstTag,
        cp.BodyLength,
        cp.AvgCommentLength,
        cp.PostsTillNow,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.Reputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        cp.PostQualityFlag,
        case 
            when cp.PostQualityFlag = 'Orphan' then 0
            else 1
        end as IsValidPost,
        row_number() over(partition by cp.PostTypeId order by cp.Score desc, cp.CreationDate desc) as PostRankByType
    from ComplexPostAnalysis cp
    left join Users u on u.Id = cp.OwnerUserId
    left join UserBadgeSummary ub on ub.UserId = cp.OwnerUserId
    left join UserActivityWindow ua on ua.UserId = cp.OwnerUserId
    where cp.PostsTillNow > 5
)

select * from FinalSelectedPosts
where PostRankByType <= 10
order by PostTypeId, Score desc, CreationDate desc

union all

select 
    p.Id as PostId,
    p.PostTypeId,
    u.DisplayName as OwnerName,
    p.CreationDate,
    p.Score,
    null as FirstTag,
    length(p.Body) as BodyLength,
    0 as AvgCommentLength,
    1 as PostsTillNow,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as Reputation,
    0 as QuestionsPosted,
    0 as AnswersPosted,
    0 as CommentsMade,
    'Normal' as PostQualityFlag,
    1 as IsValidPost,
    null as PostRankByType
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 3
and p.Score > (select avg(Score) from Posts where PostTypeId = 3)
order by p.Score desc
limit 5;