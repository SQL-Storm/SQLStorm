-- {"query": "318.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1621} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count
    where r.Level < 3
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyEarned,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId = 8 -- BountyStart
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopPostsWithWindow as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView,
        dense_rank() over (order by p.CreationDate desc) as RankByCreationDate,
        count(*) over (partition by p.PostTypeId) as TotalPostsOfType
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
ClosedQuestionsWithReasons as (
    select 
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
AnswerStatsPerQuestion as (
    select 
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        max(p.Score) as MaxAnswerScore,
        avg(p.Score) as AvgAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 2
    group by p.ParentId
),
UserBadgeSummary as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
ComplexUserStats as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyEarned,
        ua.MaxAnswerScore,
        ua.AvgQuestionScore,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.DistinctBadges,0) as DistinctBadges,
        case 
            when ua.Reputation > 10000 then 'Expert'
            when ua.Reputation between 1000 and 10000 then 'Intermediate'
            else 'Beginner'
        end as UserLevel,
        row_number() over (order by ua.Reputation desc, ua.TotalBountyEarned desc) as UserRank
    from UserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
),
FinalSelection as (
    select 
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostTypeId,
        u.DisplayName as OwnerName,
        cs.UserLevel,
        cs.GoldBadges,
        cs.SilverBadges,
        cs.BronzeBadges,
        cs.DistinctBadges,
        cs.UserRank,
        aq.AnswerCount,
        aq.MaxAnswerScore,
        aq.AvgAnswerScore,
        cq.CloseReason,
        cq.CloseDate,
        cq.ClosedByUserName,
        case 
            when p.Tags is null then array[]::varchar[]
            else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')
        end as TagArray
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join ComplexUserStats cs on cs.UserId = u.Id
    left join AnswerStatsPerQuestion aq on aq.QuestionId = p.Id and p.PostTypeId = 1
    left join ClosedQuestionsWithReasons cq on cq.PostId = p.Id
    where p.PostTypeId = 1
)
select 
    fs.PostId,
    fs.Title,
    fs.Score,
    fs.ViewCount,
    fs.CreationDate,
    fs.OwnerName,
    fs.UserLevel,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.DistinctBadges,
    fs.UserRank,
    fs.AnswerCount,
    fs.MaxAnswerScore,
    fs.AvgAnswerScore,
    fs.CloseReason,
    fs.CloseDate,
    fs.ClosedByUserName,
    array_to_string(fs.TagArray, ', ') as Tags,
    length(fs.Title) as TitleLength,
    case 
        when fs.CloseReason is not null then 'Closed'
        else 'Open'
    end as PostStatus,
    (select count(*) from Comments c where c.PostId = fs.PostId and (c.Text ilike '%performance%' or c.Text ilike '%benchmark%')) as PerformanceCommentsCount,
    (select count(*) from Votes v where v.PostId = fs.PostId and v.VoteTypeId = 2) as UpVotesCount,
    (select count(*) from Votes v where v.PostId = fs.PostId and v.VoteTypeId = 3) as DownVotesCount
from FinalSelection fs
where fs.Score > 5
order by fs.UserRank, fs.Score desc, fs.ViewCount desc
limit 100;