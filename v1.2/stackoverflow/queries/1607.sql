with RecentHighlyScoredQuestions as (
    select p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rn,
        regexp_replace(substr(coalesce(p.Title, ''), 1, 50), '[^\\w\\s]', '', 'g') as SafeTitleFragment
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
      and p.Score >= 10
),
UserBadgeCounts as (
    select b.UserId, b.Class, count(*) as BadgeCount
    from Badges b
    where b.Date > cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
    group by b.UserId, b.Class
),
TopBadgeTotals as (
    select ubc.UserId,
           sum(case when ubc.Class = 1 then ubc.BadgeCount else 0 end) as GoldCount,
           sum(case when ubc.Class = 2 then ubc.BadgeCount else 0 end) as SilverCount,
           sum(case when ubc.Class = 3 then ubc.BadgeCount else 0 end) as BronzeCount
    from UserBadgeCounts ubc
    group by ubc.UserId
),
UserPostCounts as (
    select u.Id as UserId,
          count(distinct p.Id) as TotalPosts,
          sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
          sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
          avg(p.Score) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation, tbody.GoldCount, tbody.SilverCount, tbody.BronzeCount,
           upc.QuestionCount, upc.AnswerCount, upc.AvgPostScore
    from Users u
    join TopBadgeTotals tbody on tbody.UserId = u.Id
    join UserPostCounts upc on upc.UserId = u.Id
    where tbody.GoldCount >= 3 and upc.QuestionCount >= 10 and u.Reputation > 1000
),
DuplicatedDuplicateQuestions as (
    select pl.PostId, count(pl.RelatedPostId) as DuplicateLinksCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
    having count(pl.RelatedPostId) > 1
)
select
    tu.Id as TopUserId,
    tu.DisplayName as TopUserDisplayName,
    rq.Id as QuestionId,
    rq.Title as QuestionTitle,
    rq.Score as QuestionScore,
    rq.CreationDate as QuestionCreationDate,
    tu.Reputation,
    tu.GoldCount,
    tu.SilverCount,
    tu.BronzeCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.AvgPostScore,
    dbc.DuplicateLinksCount
from TopUsers tu
join RecentHighlyScoredQuestions rq on rq.OwnerUserId = tu.Id and rq.rn = 1
left join DuplicatedDuplicateQuestions dbc on dbc.PostId = rq.Id
order by tu.Reputation desc, rq.Score desc;