with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then b.Id end) as GoldBadges,
        count(case when b.Class = 2 then b.Id end) as SilverBadges,
        count(case when b.Class = 3 then b.Id end) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by
        u.Id, u.DisplayName, b.Date
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        tag.Tag as Tag,
        count(*) as PostsCount
    from
        Posts p
        cross join lateral (
            select
                trim(x) as Tag
            from
                regexp_split_to_table(trim(both '<>' from p.Tags), '><') as t(x)
        ) tag
    where
        p.PostTypeId = 1 and p.OwnerUserId is not null
    group by
        p.OwnerUserId, tag.Tag
),
TopAnswersWithFlag as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        case when exists (
            select 1
            from Votes v
            where v.PostId = a.Id and v.VoteTypeId = 4
        ) then true else false end as HasOffensiveVote
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
        a.OwnerUserId,
        a.Score,
        a.HasOffensiveVote,
        row_number() over (partition by q.Id order by a.Score desc, a.AnswerId) as AnswerRank
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
        left join CloseReasonTypes crt on crt.Id = CAST(ph.Comment AS integer)
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
        pl.LinkTypeId = 3
),
CombinedTopUsers as (
    select distinct u.Id, u.DisplayName,
        coalesce(b.GoldBadges,0) as GoldBadges, coalesce(b.SilverBadges,0) as SilverBadges, coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(co.PostCount,0) as QuestionCount,
        case when max(v.Uptime) over (partition by u.Id) > DATE '2015-01-01' then 1 else 0 end as RecentActivityFlag,
        u.Reputation
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
            select Id as UserId, max(LASTACCESSDATE) as Uptime
            from Users
            group by Id
        ) v on v.UserId = u.Id
    where u.Reputation > 1000
)
select
    ctu.Id as UserId,
    ctu.DisplayName,
    concat_ws(' | ',
        'Rep:'||CAST(ctu.Reputation AS varchar),
        'G:'||CAST(ctu.GoldBadges AS varchar),
        'S:'||CAST(ctu.SilverBadges AS varchar),
        'B:'||CAST(ctu.BronzeBadges AS varchar),
        'Q:'||CAST(ctu.QuestionCount AS varchar),
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
        select ut.Tag, ut.PostsCount 
        from UserTopTags ut
        where ut.UserId = ctu.Id
        order by ut.PostsCount desc
        limit 1
    ) topTag on true
    left join lateral (
        select qa.QuestionId, qa.QuestionTitle, qa.AnswerId, qa.OwnerUserId, qa.Score, qa.HasOffensiveVote, qa.AnswerRank
        from QuestionRankedAnswers qa
        where qa.OwnerUserId = ctu.Id
          and qa.AnswerRank = 1
        order by qa.Score desc
        limit 1
    ) qa on true
    left join ClosedQuestionsWithHistory cq on cq.Id = qa.QuestionId
    left join DuplicateLinksCTE dl on dl.PostId = qa.QuestionId
where
    qa.AnswerId is not null 
    and (qa.HasOffensiveVote = false or qa.HasOffensiveVote is null)
order by
    ctu.GoldBadges desc,
    qa.Score desc,
    ctu.Id
limit 100;