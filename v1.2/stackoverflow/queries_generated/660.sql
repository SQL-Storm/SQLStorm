-- {"query": "660.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1360} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.TagName order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where t.TagName is not null
),
TopTagPosts as (
    select * from RecursiveTagCounts where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        sum(p.Score) as TotalPostScore,
        max(p.Score) as MaxPostScore,
        avg(p.Score) as AvgPostScore,
        count(distinct c.Id) as TotalComments,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
UserBadgesWithRanks as (
    select
        ub.UserId,
        ub.Class,
        ub.BadgeCount,
        rank() over (partition by ub.Class order by ub.BadgeCount desc) as BadgeRank
    from UserBadgeCounts ub
),
RecentEdits as (
    select
        ph.PostId,
        ph.UserId,
        ph.UserDisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p.Title as RelatedPostTitle,
        p.PostTypeId as RelatedPostTypeId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.RelatedPostId
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation
    from Posts q
    left join (
        select
            p.ParentId,
            count(*) as AnswerCount,
            max(p.Score) as MaxAnswerScore,
            avg(p.Score) as AvgAnswerScore
        from Posts p
        where p.PostTypeId = 2
        group by p.ParentId
    ) a on a.ParentId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1
)
select
    tt.TagName,
    tt.PostId,
    tt.Score,
    tt.ViewCount,
    tt.CreationDate,
    tt.DisplayName as OwnerDisplayName,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalPostScore,
    ubwr.BadgeCount as GoldBadges,
    ubwr2.BadgeCount as SilverBadges,
    ubwr3.BadgeCount as BronzeBadges,
    re.UserDisplayName as LastEditor,
    re.CreationDate as LastEditDate,
    re.Comment as LastEditComment,
    pld.LinkTypeName,
    pld.RelatedPostTitle,
    pld.RelatedPostTypeId,
    qwa.AnswerCount as QuestionAnswerCount,
    qwa.MaxAnswerScore,
    qwa.AvgAnswerScore,
    case
        when tt.Score > 100 then 'Popular'
        when tt.Score between 50 and 100 then 'Moderate'
        else 'Low'
    end as PopularityCategory,
    coalesce(ups.UpVotes,0) - coalesce(ups.DownVotes,0) as NetVotes,
    case 
        when ups.AvgPostScore is null then 0
        else round(ups.AvgPostScore,2)
    end as RoundedAvgScore,
    case 
        when tt.ViewCount > 10000 then 'High Traffic'
        when tt.ViewCount > 1000 then 'Medium Traffic'
        else 'Low Traffic'
    end as TrafficCategory
from TopTagPosts tt
left join UserPostStats ups on ups.UserId = tt.OwnerUserId
left join UserBadgesWithRanks ubwr on ubwr.UserId = tt.OwnerUserId and ubwr.Class = 1
left join UserBadgesWithRanks ubwr2 on ubwr2.UserId = tt.OwnerUserId and ubwr2.Class = 2
left join UserBadgesWithRanks ubwr3 on ubwr3.UserId = tt.OwnerUserId and ubwr3.Class = 3
left join RecentEdits re on re.PostId = tt.PostId and re.rn = 1
left join PostLinkDetails pld on pld.PostId = tt.PostId
left join QuestionsWithAnswers qwa on qwa.QuestionId = tt.PostId
where tt.TagName is not null
order by tt.TagName, tt.Score desc, tt.ViewCount desc
limit 100;