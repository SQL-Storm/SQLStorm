-- {"query": "1292.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1256} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class=1) as GoldBadges,
        count(b.Id) filter (where b.Class=2) as SilverBadges,
        count(b.Id) filter (where b.Class=3) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as rn
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by
        u.Id, u.DisplayName
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,
        count(*) as PostsCount
    from
        Posts p
    where
        p.PostTypeId = 1 and p.OwnerUserId is not null
    group by
        p.OwnerUserId, Tag
),
TopAnswersWithFlag as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        exists (
            select 1
            from Votes v
            where v.PostId = a.Id and v.VoteTypeId = 4 -- Offensive vote
        ) as HasOffensiveVote
    from
        Posts a
    where
        a.PostTypeId = 2
),
QuestionRankedAnswers as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        a.AnswerId,
        a.Score,
        a.HasOffensiveVote,
        row_number() over (partition by q.Id order by a.Score desc nulls last, a.AnswerId) as AnswerRank
    from
        Posts q
        left join TopAnswersWithFlag a on a.QuestionId = q.Id
    where
        q.PostTypeId = 1
),
ClosedQuestionsWithHistory as (
    select
        q.Id,
        q.Title,
        q.Tags,
        ph.Comment as CloseReason,
        crt.Name as CloseReasonName,
        ph.CreationDate as ClosedAt
    from
        Posts q
        join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
        left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where
        q.PostTypeId = 1
),
DuplicateLinksCTE as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator
    from
        PostLinks pl
        inner join Users u on u.Id = (select OwnerUserId from Posts where Id=pl.PostId)
    where
        pl.LinkTypeId = 3 -- Duplicate
),
CombinedTopUsers as (
    select distinct u.Id, u.DisplayName,
        coalesce(b.GoldBadges,0) as GoldBadges, coalesce(b.SilverBadges,0) as SilverBadges, coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(co.PostCount,0) as QuestionCount,
        case when max(v.Uptime) over (partition by u.Id) > '2015-01-01' then 1 else 0 end as RecentActivityFlag
    from
        Users u
        left join RecursiveUserBadgeCounts b on b.UserId = u.Id and b.rn = 1
        left join (
            select OwnerUserId, count(*) as PostCount
            from Posts
            where PostTypeId = 1
            group by OwnerUserId
        ) co on co.OwnerUserId = u.Id
        left join (
            select UserId, max(LASTACCESSDATE) as Uptime
            from Users
            group by UserId
        ) v on v.UserId = u.Id
    where u.Reputation > 1000
)
select
    ctu.Id as UserId,
    ctu.DisplayName,
    concat_ws(' | ',
        'Rep:'||cast(u.Reputation as varchar),
        'G:'||cast(ctu.GoldBadges as varchar),
        'S:'||cast(ctu.SilverBadges as varchar),
        'B:'||cast(ctu.BronzeBadges as varchar),
        'Q:'||cast(ctu.QuestionCount as varchar),
        case when ctu.RecentActivityFlag = 1 then 'Active' else 'Inactive' end
    ) as UserStats,
    topTag.Tag,
    topTag.PostsCount,
    qa.QuestionId,
    qa.QuestionTitle,
    qa.AnswerId,
    qa.Score as AnswerScore,
    qa.HasOffensiveVote,
    cq.ClosedAt,
    cq.CloseReasonName,
    dl.RelatedPostId as DuplicateOf
from
    CombinedTopUsers ctu
    join Users u on u.Id = ctu.Id
    left join lateral (
        select Tag, PostsCount 
        from UserTopTags ut
        where ut.UserId = ctu.Id
        order by PostsCount desc
        limit 1
    ) topTag on true
    left join lateral (
        select qa.*
        from QuestionRankedAnswers qa
        where qa.OwnerUserId = ctu.Id
          and qa.AnswerRank = 1
        order by qa.Score desc nulls last
        limit 1
    ) qa on true
    left join ClosedQuestionsWithHistory cq on cq.Id = qa.QuestionId
    left join DuplicateLinksCTE dl on dl.PostId = qa.QuestionId
where
    qa.AnswerId is not null 
    and (qa.HasOffensiveVote = false or qa.HasOffensiveVote is null)
order by
    ctu.GoldBadges desc,
    qa.Score desc nulls last,
    ctu.Id
limit 100;