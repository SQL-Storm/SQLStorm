-- {"query": "607.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1506} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1) as TagCount
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    where p.PostTypeId = 1
    union all
    select
        rtc.Id,
        rtc.TagName,
        rtc.Count,
        p2.Id,
        p2.Score,
        p2.ViewCount,
        p2.OwnerUserId,
        p2.CreationDate,
        array_length(string_to_array(substring(p2.Tags, 2, length(p2.Tags) - 2), '><'), 1)
    from RecursiveTagCounts rtc
    join Posts p2 on p2.ParentId = rtc.PostId and p2.PostTypeId = 2
    where p2.Score > 0
),
UserBadgeRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) as MaxBadgeClass,
        bool_or(b.TagBased = 1) as HasTagBased,
        row_number() over (partition by u.Id order by count(distinct b.Id) desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVoteStats as (
    select
        p.Id as PostId,
        p.Title,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty,
        max(v.CreationDate) as LastVoteDate
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.Title, p.OwnerUserId
),
PostCloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by ph.PostId, crt.Name
),
TopPostsByScore as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as QuestionCount,
        count(distinct a.Id) as AnswerCount,
        coalesce(sum(v.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(v.DownVotes), 0) as TotalDownVotes,
        max(p.CreationDate) as LastQuestionDate,
        max(a.CreationDate) as LastAnswerDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join PostVoteStats v on v.PostId = p.Id or v.PostId = a.Id
    group by u.Id, u.DisplayName
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    u.WebsiteUrl,
    coalesce(ub.MaxBadgeClass, 0) as HighestBadgeClass,
    coalesce(ub.BadgeCount, 0) as BadgeCount,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ts.PostId as TopQuestionId,
    ts.Title as TopQuestionTitle,
    ts.Score as TopQuestionScore,
    ts.ViewCount as TopQuestionViews,
    ts.CreationDate as TopQuestionCreationDate,
    pc.CloseReasonName,
    pc.CloseCount,
    rtc.TagName as PopularTag,
    rtc.Count as TagTotalPosts,
    rtc.PostId as TagPostId,
    rtc.Score as TagPostScore,
    rtc.ViewCount as TagPostViews,
    rtc.TagCount as TagCountInPost,
    case
        when u.LastAccessDate > now() - interval '30 days' then 'Active'
        when u.LastAccessDate > now() - interval '180 days' then 'Inactive'
        else 'Dormant'
    end as UserActivityStatus,
    case
        when ua.TotalUpVotes > ua.TotalDownVotes then 'Positive Feedback'
        when ua.TotalUpVotes = ua.TotalDownVotes then 'Neutral Feedback'
        else 'Negative Feedback'
    end as FeedbackCategory,
    string_agg(distinct lt.Name, ', ') filter (where lt.Name is not null) as LinkTypesUsed,
    coalesce(pvs.TotalBounty, 0) as TotalBountyReceived,
    pvs.LastVoteDate,
    phc.Comment as LastPostHistoryComment,
    phc.CreationDate as LastPostHistoryDate
from Users u
left join UserBadgeRanks ub on ub.UserId = u.Id and ub.BadgeRank = 1
left join UserActivitySummary ua on ua.UserId = u.Id
left join TopPostsByScore ts on ts.OwnerUserId = u.Id and ts.ScoreRank = 1
left join RecursiveTagCounts rtc on rtc.OwnerUserId = u.Id
left join PostCloseReasonCounts pc on pc.PostId = ts.PostId
left join PostVoteStats pvs on pvs.PostId = ts.PostId
left join (
    select ph1.PostId, ph1.Comment, ph1.CreationDate
    from PostHistory ph1
    join (
        select PostId, max(CreationDate) as MaxCreationDate
        from PostHistory
        group by PostId
    ) ph2 on ph1.PostId = ph2.PostId and ph1.CreationDate = ph2.MaxCreationDate
) phc on phc.PostId = ts.PostId
left join (
    select distinct pl.PostId, lt.Name
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
) lt on lt.PostId = ts.PostId
where u.Reputation > 1000
order by u.Reputation desc, ts.Score desc
limit 100;