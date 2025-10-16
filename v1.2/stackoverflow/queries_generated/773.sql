-- {"query": "773.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1426} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        array[t.TagName] as Path,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        t.Id,
        t.TagName,
        t.Count,
        r.Path || t.TagName,
        r.Level + 1
    from Tags t
    join PostLinks pl on pl.PostId = t.ExcerptPostId
    join RecursiveTagHierarchy r on r.TagName = (select TagName from Tags where Id = pl.RelatedPostId)
    where r.Level < 3
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vb.DownVotes),0) as TotalDownVotes,
        max(u.Reputation) as Reputation,
        row_number() over (order by max(u.Reputation) desc) as RankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select 
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes v
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) vb on vb.OwnerUserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName
),
TopTagsPerUser as (
    select 
        ua.UserId,
        unnest(string_to_array(regexp_replace(coalesce(p.Tags, ''), '[<>]', ' ', 'g'), ' ')) as Tag
    from UserActivity ua
    join Posts p on p.OwnerUserId = ua.UserId and p.PostTypeId = 1
    where p.Tags is not null
),
TagFrequencies as (
    select 
        UserId,
        Tag,
        count(*) as TagCount,
        rank() over (partition by UserId order by count(*) desc) as TagRank
    from TopTagsPerUser
    group by UserId, Tag
),
UserTopTags as (
    select UserId, Tag, TagCount
    from TagFrequencies
    where TagRank <= 3
),
PostScoresWithWindow as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopPostRank,
        dense_rank() over (order by p.Score desc) as GlobalScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
),
ClosedQuestionsWithReason as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.ClosedDate,
        p.Score,
        ph.Comment as CloseReasonJson,
        crt.Name as CloseReasonName
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
UsersWithBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ut.Tags as TopTags,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    psp.Id as TopPostId,
    psp.Score as TopPostScore,
    psp.ViewCount as TopPostViewCount,
    cq.Id as ClosedQuestionId,
    cq.Title as ClosedQuestionTitle,
    cq.CloseReasonName,
    cq.Score as ClosedQuestionScore,
    array_agg(distinct rth.TagName) filter (where rth.Level = 1) as RelatedTagNames,
    max(ph.CreationDate) as LastPostHistoryDate
from UserActivity ua
left join (
    select 
        UserId, 
        string_agg(Tag, ', ') as Tags
    from UserTopTags
    group by UserId
) ut on ut.UserId = ua.UserId
left join UsersWithBadgeCounts us on us.UserId = ua.UserId
left join PostScoresWithWindow psp on psp.OwnerUserId = ua.UserId and psp.UserTopPostRank = 1
left join ClosedQuestionsWithReason cq on cq.OwnerUserId = ua.UserId
left join PostHistory ph on ph.UserId = ua.UserId
left join LATERAL (
    select distinct t.TagName, 1 as Level
    from Posts p2
    cross join unnest(string_to_array(regexp_replace(coalesce(p2.Tags, ''), '[<>]', ' ', 'g'), ' ')) as t(TagName)
    where p2.OwnerUserId = ua.UserId and p2.PostTypeId = 1
) rth on true
where ua.RankByReputation <= 50
group by ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.TotalUpVotes, ua.TotalDownVotes, ut.Tags, us.GoldBadges, us.SilverBadges, us.BronzeBadges, psp.Id, psp.Score, psp.ViewCount, cq.Id, cq.Title, cq.CloseReasonName, cq.Score
order by ua.Reputation desc, ua.UserId
limit 100;