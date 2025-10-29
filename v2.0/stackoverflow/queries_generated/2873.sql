-- {"query": "2873.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1701} 

with RecursiveUserActivityCTE as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        max(b.Date) as LastBadgeDate,
        row_number() over (partition by u.Id order by ph.CreationDate desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id and b.Class = 1 -- Gold badges only
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopActiveUsers as (
    select UserId, DisplayName, Reputation, QuestionCount, AnswerCount, BadgeCount, LastBadgeDate
    from RecursiveUserActivityCTE
    where ActivityRank = 1
    and Reputation > 1000
),
PostScoreStats as (
    select 
        p.OwnerUserId,
        avg(p.Score) as AvgPostScore,
        stddev_pop(p.Score) as StdDevPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore,
        count(*) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as Questions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as Answers,
        sum(case when p.ClosedDate is not null then 1 else 0 end) as ClosedPosts
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopPosts AS (
    select 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as rn
    from Posts p
    where p.Score > 10 and p.PostTypeId in (1,2)
),
UserTagEngagement AS (
    select 
        p.OwnerUserId,
        lower(trim(regexp_split_to_table(trim(both '<>' from coalesce(p.Tags, '')), '><'))) as Tag,
        count(*) as TagPostsCount,
        sum(p.Score) as TotalTagScore
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null and p.Tags is not null
    group by p.OwnerUserId, Tag
),
UserCloseReasons AS (
    select
        ph.UserId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCast
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.UserId is not null
    group by ph.UserId, crt.Name
),
UserBadgeDistribution AS (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivitySummary AS (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        pss.TotalPosts,
        pss.Questions,
        pss.Answers,
        pss.ClosedPosts,
        u.BadgeCount as GoldBadges,
        coalesce(bdSilver.BadgeCount,0) as SilverBadges,
        coalesce(bdBronze.BadgeCount,0) as BronzeBadges,
        uae.Tag,
        uae.TagPostsCount,
        uae.TotalTagScore,
        coalesce(uc.CloseReasonName, 'No Close Votes') as CloseReason,
        coalesce(uc.CloseVotesCast,0) as CloseVotesCast,
        tp.Id as TopPostId,
        tp.Title as TopPostTitle,
        tp.Score as TopPostScore,
        tp.CreationDate as TopPostCreationDate
    from TopActiveUsers u
    left join PostScoreStats pss on pss.OwnerUserId = u.UserId
    left join UserBadgeDistribution bdSilver on bdSilver.UserId = u.UserId and bdSilver.Class = 2
    left join UserBadgeDistribution bdBronze on bdBronze.UserId = u.UserId and bdBronze.Class = 3
    left join UserTagEngagement uae on uae.OwnerUserId = u.UserId
    left join lateral (
        select CloseReasonName, CloseVotesCast
        from UserCloseReasons
        where UserId = u.UserId
        order by CloseVotesCast desc
        limit 1
    ) uc on true
    left join TopPosts tp on tp.OwnerUserId = u.UserId and tp.rn = 1
)
select
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.ClosedPosts,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    coalesce(u1.HighQuestionScore, 0) as HighestQScore,
    coalesce(u2.HighAnswerScore, 0) as HighestAScore,
    uas.Tag,
    uas.TagPostsCount,
    uas.TotalTagScore,
    uas.CloseReason,
    uas.CloseVotesCast,
    uas.TopPostId,
    uas.TopPostTitle,
    uas.TopPostScore,
    uas.TopPostCreationDate,
    -- complicated predicate example with null logic and string expressions:
    case 
        when uas.TopPostTitle is not null and uas.TopPostScore > 50 then
            concat(substr(uas.TopPostTitle,1,25), '... [HOT]')
        when uas.TopPostTitle is null then '<No Top Post>'
        else
            uas.TopPostTitle
    end as TopPostDisplayTitle,
    -- Window function for percentile rank of reputation among TopActiveUsers
    percent_rank() over (order by uas.Reputation desc) as ReputationPercentile,
    -- Correlated subquery with NOT EXISTS to find users without posts in last 180 days
    case 
        when not exists (
            select 1 
            from Posts p 
            where p.OwnerUserId = uas.UserId and p.CreationDate > now() - interval '180 days'
        ) then 'Dormant'
        else 'Active'
    end as RecentActivityStatus
from UserActivitySummary uas
left join (
    select OwnerUserId, max(Score) as HighQuestionScore
    from Posts
    where PostTypeId = 1
    group by OwnerUserId
) u1 on u1.OwnerUserId = uas.UserId
left join (
    select OwnerUserId, max(Score) as HighAnswerScore
    from Posts
    where PostTypeId = 2
    group by OwnerUserId
) u2 on u2.OwnerUserId = uas.UserId
where uas.ReputationPercentile between 0.8 and 1.0
order by uas.Reputation desc, uas.TotalPosts desc
limit 50
union
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    0,0,0,0,0,0,0,
    null,null,null,null,null,null,null,null,
    '<No Data>',
    0.0,
    'NoPosts'
from Users u
where not exists (select 1 from Posts p where p.OwnerUserId = u.Id)
order by Reputation desc
limit 10
;
