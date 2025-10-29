-- {"query": "2966.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1220}
with RecursiveUserActivity as (
    select u.Id as UserId, u.DisplayName, u.Reputation, u.CreationDate, u.Location,
        coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0) as VoteBalance,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
        (select count(*) from Comments c where c.UserId = u.Id) as CommentCount,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 1) as GoldBadges,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 2) as SilverBadges,
        (select count(*) from Badges b where b.UserId = u.Id and b.Class = 3) as BronzeBadges
    from Users u
), LatestPostEdits as (
    select ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        max(case when ph.PostHistoryTypeId in (4,5,6) then ph.UserId else null end) as LastEditorUserId
    from PostHistory ph
    group by ph.PostId
), PostScoreRankings as (
    select p.Id, p.OwnerUserId, p.PostTypeId, p.Score,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
    where p.Score is not null
), ComplexTagExplode as (
    select 
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
), PopularTagUsers as (
    select cte.TagName, rua.UserId, rua.DisplayName,
        row_number() over (partition by cte.TagName order by rua.Reputation desc) as RankPerTag
    from ComplexTagExplode cte
    join Posts p on p.Id = cte.PostId
    join RecursiveUserActivity rua on rua.UserId = p.OwnerUserId
    where rua.Reputation > 1000
), DuplicateQuestionLinks as (
    select pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId, pl.CreationDate
    from PostLinks pl 
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
), UserVoteSummary as (
    select v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCount,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCount,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoritesCount,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotesCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
)
select 
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.VoteBalance,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.CommentCount,
    rua.GoldBadges,
    rua.SilverBadges,
    rua.BronzeBadges,
    coalesce(uvs.UpVotesCount, 0) as UserUpVotes,
    coalesce(uvs.DownVotesCount, 0) as UserDownVotes,
    coalesce(uvs.FavoritesCount, 0) as UserFavorites,
    coalesce(uvs.CloseVotesCount, 0) as UserCloseVotes,
    pt.ScoreRank as UserTopPostScoreRank,
    dup.DuplicateQuestionId,
    dup.OriginalQuestionId,
    pt2.Id as PostId,
    pt2.Score,
    pt2.ScoreRank,
    pst.TagName,
    pt3.RankPerTag
from RecursiveUserActivity rua
left join UserVoteSummary uvs on uvs.UserId = rua.UserId
left join Posts p on p.OwnerUserId = rua.UserId
left join PostScoreRankings pt on pt.Id = (
    select p2.Id from Posts p2
    where p2.OwnerUserId = rua.UserId
    order by p2.Score desc
    limit 1
)
left join DuplicateQuestionLinks dup on dup.DuplicateQuestionId = (
    select min(pl2.PostId) from PostLinks pl2
    where pl2.PostId in (select Id from Posts where OwnerUserId = rua.UserId and PostTypeId = 1)
    and pl2.LinkTypeId = (select Id from LinkTypes where Name='Duplicate')
    limit 1
)
left join PostScoreRankings pt2 on pt2.OwnerUserId = rua.UserId and pt2.ScoreRank = 1
left join PopularTagUsers pt3 on pt3.UserId = rua.UserId
left join (
    select distinct TagName from PopularTagUsers
) pst on pst.TagName = pt3.TagName
where rua.Reputation > 500
  and (rua.GoldBadges + rua.SilverBadges + rua.BronzeBadges) > 5
  and rua.QuestionCount > 0
  and pt2.Score > 0
group by
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.VoteBalance,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.CommentCount,
    rua.GoldBadges,
    rua.SilverBadges,
    rua.BronzeBadges,
    uvs.UpVotesCount,
    uvs.DownVotesCount,
    uvs.FavoritesCount,
    uvs.CloseVotesCount,
    pt.ScoreRank,
    dup.DuplicateQuestionId,
    dup.OriginalQuestionId,
    pt2.Id,
    pt2.Score,
    pt2.ScoreRank,
    pst.TagName,
    pt3.RankPerTag
order by rua.Reputation desc, rua.UserId
limit 100;