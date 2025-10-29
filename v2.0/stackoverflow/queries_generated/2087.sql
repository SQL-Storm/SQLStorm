-- {"query": "2087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1425} 
with RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn
    from Posts a
    where a.PostTypeId = 2
),
QuestionStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        coalesce((select count(*) from Comments c where c.PostId = q.Id),0) as QuestionCommentsCount,
        coalesce(ra_top.Score, 0) as TopAnswerScore,
        coalesce(ra_top.CreationDate, q.CreationDate) as TopAnswerCreationDate,
        coalesce(badges_gold.GoldBadges, 0) as OwnerGoldBadges,
        coalesce(u.Reputation,0) as OwnerReputation,
        coalesce(u.DisplayName, '') as OwnerDisplayName,
        q.Tags
    from Posts q
    left join RankedAnswers ra_top on ra_top.ParentId = q.Id and ra_top.rn = 1
    left join (
        select UserId, count(*) as GoldBadges
        from Badges
        where Class = 1
        group by UserId
    ) badges_gold on badges_gold.UserId = q.OwnerUserId
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1
),
CloseStats as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as ReopenedDate,
        string_agg(distinct crt.Name, ', ' order by crt.Name) as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id::int = ph.Comment::int
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
UserVoteSummary as (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCast,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCast,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoritesCast
    from Votes v
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
),
UserBadgeStats as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as Gold,
        count(*) filter (where b.Class = 2) as Silver,
        count(*) filter (where b.Class = 3) as Bronze,
        count(*) filter (where b.TagBased = true) as TagBasedBadges
    from Badges b
    group by b.UserId
),
TagUsage as (
    select
        unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) as Tag,
        count(*) as QuestionCount,
        avg(q.ViewCount) as AvgViews,
        avg(q.Score) as AvgScore
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
    group by Tag
    having count(*) > 50
),
BadgedUsersWithHighRep as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ub.Gold,
        ub.Silver,
        ub.Bronze,
        us.UpVotesCast,
        us.DownVotesCast,
        us.FavoritesCast
    from Users u
    left join UserBadgeStats ub on ub.UserId = u.Id
    left join UserVoteSummary us on us.UserId = u.Id
    where u.Reputation > 10000 and (ub.Gold + ub.Silver + ub.Bronze) > 10
),
PostsAndLinks as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        plt.Identity,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        rp.Title as RelatedPostTitle,
        rp.PostTypeId as RelatedPostType
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts rp on rp.Id = pl.RelatedPostId
    cross join lateral (
      select p.Id as Identity
    ) plt
    where p.PostTypeId = 1
)
select
    qs.QuestionId,
    qs.Title,
    qs.OwnerDisplayName,
    qs.OwnerReputation,
    qs.QuestionScore,
    qs.ViewCount,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.QuestionCommentsCount,
    qs.TopAnswerScore,
    date_part('day', qs.TopAnswerCreationDate - qs.CreationDate) as DaysToTopAnswer,
    cs.ClosedDate,
    cs.ReopenedDate,
    cs.CloseReasons,
    tsn.TotalGoldBadges,
    tsn.TotalSilverBadges,
    tsn.TotalBronzeBadges,
    tu.Tag,
    tu.QuestionCount as TagQuestionsCount,
    tu.AvgViews as TagAvgViews,
    tu.AvgScore as TagAvgScore
from QuestionStats qs
left join CloseStats cs on cs.PostId = qs.QuestionId
left join (
    select
        u.Id,
        coalesce(ub.Gold, 0) as TotalGoldBadges,
        coalesce(ub.Silver, 0) as TotalSilverBadges,
        coalesce(ub.Bronze, 0) as TotalBronzeBadges
    from Users u
    left join UserBadgeStats ub on ub.UserId = u.Id
) tsn on tsn.Id = qs.OwnerUserId
left join TagUsage tu on tu.Tag = (
    select unnest(string_to_array(substring(qs.Tags from 2 for char_length(qs.Tags) - 2), '><'))
    order by tu.QuestionCount desc
    limit 1
)
where
    (qs.QuestionScore > 0 or qs.TopAnswerScore > 0)
    and qs.AnswerCount > 0
    and (cs.ClosedDate is null or cs.ReopenedDate is not null)
order by
    qs.AnswerCount desc,
    qs.QuestionScore desc
limit 100;