-- {"query": "2828.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1380} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        coalesce(p.Tags, '') as Tags,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > (
        select avg(Reputation) from Users
    )
),
UserBadgesCount as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
TopTagsByUser as (
    select
        rup.UserId,
        unnest(string_to_array(replace(replace(rup.Tags, '<', ''), '>', ','), ',')) as Tag,
        count(*) as TagCount
    from RecursiveUserPosts rup
    where rup.PostRank <= 50 and rup.PostTypeId = 1
    group by rup.UserId, Tag
),
RankedTags as (
    select
        tbu.UserId,
        tbu.Tag,
        tbu.TagCount,
        rank() over (partition by tbu.UserId order by tbu.TagCount desc) as TagRank
    from TopTagsByUser tbu
),
UserCommentsStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(c.Score) as AvgCommentScore,
        sum(case when c.Text ilike '%sql%' then 1 else 0 end) as SqlMentions
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserVoteStats as (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCast,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCast,
        count(*) as TotalVotesCast
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    coalesce(ub.TotalBadges,0) as TotalBadges,
    coalesce(uc.CommentCount,0) as CommentCount,
    round(coalesce(uc.AvgCommentScore,0),2) as AvgCommentScore,
    coalesce(uc.SqlMentions,0) as SqlMentionsInComments,
    coalesce(uv.UpVotesCast,0) as UpVotesCast,
    coalesce(uv.DownVotesCast,0) as DownVotesCast,
    coalesce(uv.TotalVotesCast,0) as TotalVotesCast,
    array_agg(distinct rt.Tag) filter (where rt.TagRank <= 3 and rt.Tag is not null and rt.Tag <> '') as Top3Tags,
    (select count(*)
        from Posts p
        where p.OwnerUserId = u.Id
        and p.PostTypeId = 1
        and p.CreationDate >= (current_date - interval '1 year')
        and p.Score >= (
            select percentile_cont(0.8) within group (order by Score)
            from Posts p2
            where p2.PostTypeId = 1 and p2.CreationDate >= (current_date - interval '1 year')
        )
    ) as QuestionsInTop20PercentileByScoreLastYear,
    (select count(*)
        from Posts p
        where p.OwnerUserId = u.Id
        and p.PostTypeId = 2
        and p.Score >= 10
        and not exists (
            select 1 from PostLinks pl
            where pl.PostId = p.Id and pl.LinkTypeId = 3
        )
    ) as HighScoreNonDuplicateAnswers,
    (select coalesce(max(ph.CreationDate), timestamp '1900-01-01')
        from PostHistory ph
        join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name ilike '%Closed%'
        where ph.PostId in (
            select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1
        )
    ) as LastClosedQuestionDate,
    round(
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1)+
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2)*0.5, 2
    ) as WeightedAvgPostScore,
    coalesce((
        select sum(vb.BountyAmount) from Votes vb
        where vb.UserId = u.Id and vb.VoteTypeId = 8
    ),0) as TotalBountyStarted,
    coalesce((
        select sum(vb.BountyAmount) from Votes vb
        where vb.UserId = u.Id and vb.VoteTypeId = 9
    ),0) as TotalBountyClosed,
    coalesce(pct.PercentileRank, 0) as ReputationPercentileRank
from Users u
left join UserBadgesCount ub on ub.UserId = u.Id
left join UserCommentsStats uc on uc.UserId = u.Id
left join UserVoteStats uv on uv.UserId = u.Id
left join RankedTags rt on rt.UserId = u.Id
left join (
    select
        Id,
        cume_dist() over (order by Reputation) as PercentileRank
    from Users
) pct on pct.Id = u.Id
where u.Reputation > 1000
order by ReputationPercentileRank desc, TotalBadges desc, WeightedAvgPostScore desc
limit 100;