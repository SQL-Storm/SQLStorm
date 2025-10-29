-- {"query": "2134.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1522}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Id as BadgeId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
),
TopBadges as (
    select UserId, BadgeId, BadgeName, Class
    from RecursiveUserBadges
    where rn <= 3
),
PostAggregates as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.Tags, '') as Tags,
        length(coalesce(p.Body, '')) as BodyLength,
        row_number() over (partition by p.Id order by length(coalesce(p.Tags, '')) desc) as TagFreqRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopTags as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count
    from Tags t
    where t.Count > (select avg(Count) from Tags)
),
PostLinkInfo as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as RelatedPostsCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.CreationDate,
        count(*) over (
            partition by u.Id 
            order by extract(epoch from p.CreationDate)
            range between (30 * 24 * 60 * 60) preceding and current row
        ) as PostsLast30Days
    from Users u
    join Posts p on p.OwnerUserId = u.Id
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReasonName,
        ph.Comment as CloseReasonIdText
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
QuestionsWithAnswersAndVotes as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(q.Tags, '') as Tags,
        count(distinct a.Id) as AnswerCount,
        sum(coalesce(vtUp.CountUpVotes,0)) as TotalAnswerUpVotes,
        sum(coalesce(vtDown.CountDownVotes,0)) as TotalAnswerDownVotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join (
        select
            v.PostId,
            count(*) as CountUpVotes
        from Votes v
        where v.VoteTypeId = 2
        group by v.PostId
    ) vtUp on vtUp.PostId = a.Id
    left join (
        select
            v.PostId,
            count(*) as CountDownVotes
        from Votes v
        where v.VoteTypeId = 3
        group by v.PostId
    ) vtDown on vtDown.PostId = a.Id
    where q.PostTypeId = 1
    group by q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
TopUsersByActivity as (
    select 
        ua.UserId, 
        ua.DisplayName,
        max(ua.PostsLast30Days) as MaxPosts30Days,
        count(distinct b.Id) as BadgeCount
    from UserActivityWindow ua
    left join Badges b on b.UserId = ua.UserId
    group by ua.UserId, ua.DisplayName
    having max(ua.PostsLast30Days) > 5
),
UserTags as (
    select 
        u.Id as UserId, 
        unnest(string_to_array(coalesce(p.Tags, ''), '><')) as TagName
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
),
UserTopTags as (
    select 
        ut.UserId, 
        ut.TagName, 
        count(*) as TagUsage,
        dense_rank() over (partition by ut.UserId order by count(*) desc) as TagRank
    from UserTags ut
    group by ut.UserId, ut.TagName
    having count(*) > 1
)
select
    q.QuestionId,
    u.DisplayName as QuestionOwner,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.TotalAnswerUpVotes,
    q.TotalAnswerDownVotes,
    coalesce(ct.CloseReasonName, 'Open') as CloseReason,
    coalesce(pl.RelatedPostsCount, 0) as RelatedPosts,
    coalesce(pl.DuplicateCount, 0) as DuplicateLinks,
    string_agg(distinct (t.TagName || '(' || t.Count || ')'), ', ') as PopularTags,
    string_agg(distinct (tb.BadgeName || ':' || tb.Class), ', ') as TopBadges,
    case when q.QuestionScore > 10 then 'Hot Question' else 'Normal' end as QuestionCategory,
    ut.TopTagNames,
    topu.MaxPosts30Days,
    topu.BadgeCount
from QuestionsWithAnswersAndVotes q
left join Users u on u.Id = q.OwnerUserId
left join ClosedQuestions ct on ct.PostId = q.QuestionId
left join PostLinkInfo pl on pl.PostId = q.QuestionId
left join (
    select 
        UserId, 
        string_agg(TagName, ', ') as TopTagNames
    from (
        select 
            UserId, 
            TagName,
            TagRank
        from UserTopTags
        where TagRank <= 3
    ) uts
    group by UserId
) ut on ut.UserId = q.OwnerUserId
left join TopBadges tb on tb.UserId = q.OwnerUserId
left join TopUsersByActivity topu on topu.UserId = q.OwnerUserId
left join Tags t on t.TagName = any(string_to_array(coalesce(q.Tags, ''), '><'))
group by
    q.QuestionId,
    u.DisplayName,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.TotalAnswerUpVotes,
    q.TotalAnswerDownVotes,
    ct.CloseReasonName,
    pl.RelatedPostsCount,
    pl.DuplicateCount,
    ut.TopTagNames,
    topu.MaxPosts30Days,
    topu.BadgeCount
order by q.QuestionCreationDate desc
limit 100;