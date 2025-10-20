with RecursiveUserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc) as RecentBadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Date
),
TopUserPosts as (
    select 
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as PostRank
    from Posts p
    where p.OwnerUserId is not null
),
AcceptedAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AcceptedAnswerDate
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
),
CloseReasonCounts as (
    select 
        pht.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(distinct pht.PostId) as ClosedPostCount
    from PostHistory pht
    join CloseReasonTypes crt on cast(crt.Id as text) = pht.Comment
    where pht.PostHistoryTypeId = 10
    group by pht.Comment, crt.Name
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(c.Id) as CommentCount,
        sum(vt_count.UpVotes) as TotalUpVotes,
        sum(vt_count.DownVotes) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select 
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt_count on vt_count.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
UserCommentTextStats as (
    select 
        c.UserId,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.Text like '%SQL%' then 1 else 0 end) as CommentsMentioningSQL,
        count(c.Id) as TotalComments
    from Comments c
    group by c.UserId
),
PostTagExplode as (
    select 
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.Tags is not null and p.PostTypeId = 1
),
TagPopularity as (
    select 
        Tag,
        count(distinct PostId) as QuestionCount,
        row_number() over (order by count(distinct PostId) desc) as PopularityRank
    from PostTagExplode
    group by Tag
),
UserTagEngagement as (
    select 
        u.Id as UserId,
        p.Id as PostId,
        pt.Tag,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesOnPostsWithTag,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesOnPostsWithTag
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    join PostTagExplode pt on pt.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, p.Id, pt.Tag
),
UserTagSummary as (
    select 
        UserId,
        Tag,
        sum(UpVotesOnPostsWithTag) as TotalUpVotes,
        sum(DownVotesOnPostsWithTag) as TotalDownVotes,
        (sum(UpVotesOnPostsWithTag) - sum(DownVotesOnPostsWithTag)) as NetVotes
    from UserTagEngagement
    group by UserId, Tag
),
TopTagsPerUser as (
    select 
        uts.UserId,
        uts.Tag,
        uts.NetVotes,
        row_number() over (partition by uts.UserId order by uts.NetVotes desc) as TagRank
    from UserTagSummary uts
    where uts.NetVotes is not null
),
QuestionsWithCloseState as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        case when pht.PostId is not null then true else false end as IsClosed,
        crt.Name as CloseReasonName
    from Posts q
    left join PostHistory pht on pht.PostId = q.Id and pht.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on cast(crt.Id as text) = pht.Comment
    where q.PostTypeId = 1
),
UserAnswerPerformance as (
    select 
        a.OwnerUserId as UserId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        count(distinct case when a.Id = q.AcceptedAnswerId then a.Id end) as AcceptedAnswerCount
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
    group by a.OwnerUserId
)
select 
    uaw.UserId,
    uaw.DisplayName,
    uaw.Reputation,
    uaw.QuestionCount,
    uaw.AnswerCount,
    uaw.CommentCount,
    coalesce(uc.AvgCommentLength,0) as AvgCommentLength,
    coalesce(uc.CommentsMentioningSQL,0) as CommentsMentioningSQL,
    rbc.GoldBadges,
    rbc.SilverBadges,
    rbc.BronzeBadges,
    aap.AcceptedAnswerScore,
    aap.AcceptedAnswerDate,
    cwc.IsClosed,
    cwc.CloseReasonName,
    uap.AnswerCount as UserAnswerCount,
    uap.AvgAnswerScore,
    uap.AcceptedAnswerCount,
    ttp.Tag as TopTag,
    ttp.NetVotes as TopTagNetVotes,
    tp.PopularityRank as TopTagPopularityRank
from UserActivityWindow uaw
left join UserCommentTextStats uc on uc.UserId = uaw.UserId
left join RecursiveUserBadgeCounts rbc on rbc.UserId = uaw.UserId and rbc.RecentBadgeRank = 1
left join AcceptedAnswerStats aap on aap.OwnerUserId = uaw.UserId
left join QuestionsWithCloseState cwc on cwc.OwnerUserId = uaw.UserId
left join UserAnswerPerformance uap on uap.UserId = uaw.UserId
left join TopTagsPerUser ttp on ttp.UserId = uaw.UserId and ttp.TagRank = 1
left join TagPopularity tp on tp.Tag = ttp.Tag
where uaw.UserRank <= 100
order by uaw.Reputation desc, uaw.UserId
limit 100;